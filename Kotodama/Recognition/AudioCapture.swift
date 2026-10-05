//
//  AudioCapture.swift
//  Kotodama
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import AVFAudio
import Foundation
import Observation

/// Microphone capture through `AVAudioEngine`. Publishes a smoothed level for the UI.
@MainActor
@Observable
final class AudioCapture {
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private(set) var isRunning = false
    /// Smoothed microphone level in 0...1.
    private(set) var level: Float = 0

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// Starts the microphone and returns the buffer stream. Call `stop()` to end it.
    func start() throws -> AsyncStream<AVAudioPCMBuffer> {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw RecognitionError.audioEngine(error.localizedDescription)
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecognitionError.audioEngine(String(localized: "No microphone is available on this device."))
        }

        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream(bufferingPolicy: .unbounded)
        self.continuation = continuation
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let copy = buffer.cloned() else { return }
            continuation.yield(copy)
            let level = buffer.rmsLevel
            Task { @MainActor in self?.updateLevel(level) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw RecognitionError.audioEngine(error.localizedDescription)
        }
        isRunning = true
        return stream
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        isRunning = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func updateLevel(_ newLevel: Float) {
        // Fast attack, slow release keeps the meter lively without flicker.
        level = newLevel > level ? newLevel : level * 0.85 + newLevel * 0.15
    }
}

/// Streams a recorded audio file as PCM buffers, for imports, samples and tests.
enum AudioFileReader {
    struct Source {
        let stream: AsyncStream<AVAudioPCMBuffer>
        let duration: Double
        let format: AVAudioFormat
    }

    static func open(_ url: URL, chunkFrames: AVAudioFrameCount = 4096, realTime: Bool = false) throws -> Source {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let duration = Double(file.length) / format.sampleRate
        let reader = FileReader(file: file)
        let stream = AsyncStream<AVAudioPCMBuffer> { continuation in
            let task = Task.detached {
                do {
                    while let buffer = try reader.next(chunkFrames: chunkFrames) {
                        try Task.checkCancellation()
                        continuation.yield(buffer)
                        if realTime {
                            try await Task.sleep(for: .seconds(Double(buffer.frameLength) / format.sampleRate))
                        }
                    }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return Source(stream: stream, duration: duration, format: format)
    }

    /// Serialises access to the non-Sendable `AVAudioFile`.
    private final class FileReader: @unchecked Sendable {
        private let file: AVAudioFile
        private let lock = NSLock()

        init(file: AVAudioFile) { self.file = file }

        func next(chunkFrames: AVAudioFrameCount) throws -> AVAudioPCMBuffer? {
            lock.lock(); defer { lock.unlock() }
            guard file.framePosition < file.length,
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunkFrames) else { return nil }
            try file.read(into: buffer)
            return buffer.frameLength > 0 ? buffer : nil
        }
    }
}
