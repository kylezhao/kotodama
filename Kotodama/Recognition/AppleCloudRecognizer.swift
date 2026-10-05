//
//  AppleCloudRecognizer.swift
//  Kotodama
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import AVFAudio
import Foundation
import Speech

/// Server-based recognition through `SFSpeechRecognizer`, Apple's cloud speech model.
/// Supports more locales than the on-device modules; each request is limited to about a minute.
final class AppleCloudRecognizer: SpeechRecognizer {
    let mode: RecognitionMode = .cloud

    private let baseDescriptor = RecognizerDescriptor(mode: .cloud, displayName: "Apple Speech Servers", modelID: "SFSpeechRecognizer (server)")

    func descriptor(for language: LanguageOption) async -> RecognizerDescriptor { baseDescriptor }

    func availability(for language: LanguageOption) async -> RecognizerAvailability {
        // `isAvailable` is updated asynchronously after creation, so only the locale check is reliable here.
        // Network problems surface when a transcription actually runs.
        guard SFSpeechRecognizer(locale: language.locale) != nil else {
            return .unavailable(reason: RecognitionError.unsupportedLanguage(language.name).localizedDescription)
        }
        return .ready
    }

    func prepare(language: LanguageOption, progress: @escaping @Sendable (Double) -> Void) async throws {
        try await Self.authorize()
        progress(1)
    }

    func transcribe(_ audio: AsyncStream<AVAudioPCMBuffer>, language: LanguageOption) -> AsyncThrowingStream<RecognitionUpdate, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(audio, language: language) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Pipeline

    private func run(
        _ audio: AsyncStream<AVAudioPCMBuffer>,
        language: LanguageOption,
        emit: @escaping @Sendable (RecognitionUpdate) -> Void
    ) async throws {
        try await Self.authorize()
        guard let recognizer = SFSpeechRecognizer(locale: language.locale) else {
            throw RecognitionError.unsupportedLanguage(language.name)
        }
        // Availability is reported asynchronously and starts out false. Wait a little, then proceed either
        // way: a genuinely unreachable server fails the recognition task with a proper error.
        for _ in 0..<30 where !recognizer.isAvailable {
            try await Task.sleep(for: .milliseconds(100))
        }

        let clock = ContinuousClock()
        let start = clock.now
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        request.addsPunctuation = true
        request.taskHint = .dictation

        let (results, resultContinuation) = AsyncThrowingStream<SFSpeechRecognitionResult, any Error>.makeStream()
        let recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                resultContinuation.yield(result)
                if result.isFinal { resultContinuation.finish() }
            }
            if let error {
                resultContinuation.finish(throwing: error)
            }
        }

        let feeder = Task {
            var frames: Double = 0
            var sampleRate: Double = 0
            for await buffer in audio {
                if Task.isCancelled { break }
                frames += Double(buffer.frameLength)
                sampleRate = buffer.format.sampleRate
                request.append(buffer)
            }
            request.endAudio()
            return Duration.seconds(sampleRate > 0 ? frames / sampleRate : 0)
        }

        var firstResultLatency: Duration?
        var finalText = ""
        do {
            for try await result in results {
                try Task.checkCancellation()
                let text = result.bestTranscription.formattedString
                if firstResultLatency == nil, !text.isEmpty { firstResultLatency = clock.now - start }
                if result.isFinal {
                    finalText = text
                    emit(.finalized(text))
                } else {
                    emit(.volatile(text))
                }
            }
        } catch {
            recognitionTask.cancel()
            feeder.cancel()
            throw error
        }

        let audioDuration = await feeder.value
        if finalText.isEmpty { throw RecognitionError.noSpeechDetected }
        emit(.completed(RecognitionMetrics(
            engine: baseDescriptor,
            audioDuration: audioDuration,
            wallClock: clock.now - start,
            firstResultLatency: firstResultLatency,
            segmentCount: 1
        )))
    }

    static func authorize() async throws {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            return
        case .denied, .restricted:
            throw RecognitionError.speechRecognitionDenied
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
            if !granted { throw RecognitionError.speechRecognitionDenied }
        @unknown default:
            throw RecognitionError.speechRecognitionDenied
        }
    }

    static func map(_ error: any Error) -> RecognitionError {
        if error is CancellationError { return .cancelled }
        if let known = error as? RecognitionError { return known }
        let nsError = error as NSError
        // kAFAssistantErrorDomain 1110 is "No speech detected"; 203 is a retryable server failure.
        if nsError.code == 1110 { return .noSpeechDetected }
        if nsError.code == 203 { return .recognizer(String(localized: "Apple's speech servers asked us to retry. Try again.")) }
        return .recognizer(error.localizedDescription)
    }
}
