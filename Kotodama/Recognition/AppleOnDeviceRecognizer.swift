//
//  AppleOnDeviceRecognizer.swift
//  Kotodama
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import AVFAudio
import Foundation
import Speech

/// On-device recognition through `SpeechAnalyzer`.
///
/// Uses `SpeechTranscriber` for the languages it supports and falls back to `DictationTranscriber`,
/// which covers more regional varieties and dialects. Both run entirely on the device.
actor AppleOnDeviceRecognizer: SpeechRecognizer {
    nonisolated let mode: RecognitionMode = .onDevice

    enum Module: Sendable {
        case transcriber
        case dictation

        var descriptor: RecognizerDescriptor {
            switch self {
            case .transcriber:
                RecognizerDescriptor(mode: .onDevice, displayName: "Apple Speech", modelID: "SpeechTranscriber (on-device)")
            case .dictation:
                RecognizerDescriptor(mode: .onDevice, displayName: "Apple Dictation", modelID: "DictationTranscriber (on-device)")
            }
        }
    }

    /// Picks the richest on-device module that supports the language.
    func module(for language: LanguageOption) async -> Module? {
        if await SpeechTranscriber.supportedLocale(equivalentTo: language.locale) != nil {
            return .transcriber
        }
        let dictationLocales = await DictationTranscriber.supportedLocales
        if dictationLocales.contains(where: { $0.identifier(.bcp47) == language.id }) {
            return .dictation
        }
        return nil
    }

    func descriptor(for language: LanguageOption) async -> RecognizerDescriptor {
        (await module(for: language))?.descriptor
            ?? RecognizerDescriptor(mode: .onDevice, displayName: "Apple Speech", modelID: "unsupported")
    }

    func availability(for language: LanguageOption) async -> RecognizerAvailability {
        guard let module = await module(for: language) else {
            return .unavailable(reason: RecognitionError.unsupportedLanguage(language.name).localizedDescription)
        }
        let status = await AssetInventory.status(forModules: makeModules(module, locale: language.locale))
        switch status {
        case .installed: return .ready
        case .supported, .downloading: return .needsDownload
        case .unsupported: return .unavailable(reason: RecognitionError.unsupportedLanguage(language.name).localizedDescription)
        @unknown default: return .needsDownload
        }
    }

    func prepare(language: LanguageOption, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let module = await module(for: language) else {
            throw RecognitionError.unsupportedLanguage(language.name)
        }
        try await ensureAssets(for: makeModules(module, locale: language.locale), progress: progress)
    }

    nonisolated func transcribe(_ audio: AsyncStream<AVAudioPCMBuffer>, language: LanguageOption) -> AsyncThrowingStream<RecognitionUpdate, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(audio, language: language) { update in continuation.yield(update) }
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
        guard let choice = await module(for: language) else {
            throw RecognitionError.unsupportedLanguage(language.name)
        }
        let clock = ContinuousClock()
        let start = clock.now
        let tracker = ResultTracker(start: start, clock: clock, emit: emit)

        let modules = makeModules(choice, locale: language.locale)
        try await ensureAssets(for: modules, progress: { _ in })
        let analyzer = SpeechAnalyzer(modules: modules)
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules)
        let (inputSequence, builder) = AsyncStream<AnalyzerInput>.makeStream()

        let resultsTask: Task<Void, any Error>
        switch choice {
        case .transcriber:
            guard let transcriber = modules.first as? SpeechTranscriber else { throw RecognitionError.recognizer("Module setup failed.") }
            resultsTask = Task {
                for try await result in transcriber.results {
                    await tracker.record(text: String(result.text.characters), isFinal: result.isFinal)
                }
            }
        case .dictation:
            guard let dictation = modules.first as? DictationTranscriber else { throw RecognitionError.recognizer("Module setup failed.") }
            resultsTask = Task {
                for try await result in dictation.results {
                    await tracker.record(text: String(result.text.characters), isFinal: result.isFinal)
                }
            }
        }

        try await analyzer.start(inputSequence: inputSequence)

        var converter = BufferConverter()
        var frames: Double = 0
        var sampleRate: Double = 0
        for await buffer in audio {
            try Task.checkCancellation()
            frames += Double(buffer.frameLength)
            sampleRate = buffer.format.sampleRate
            let converted = try format.map { try converter.convert(buffer, to: $0) } ?? buffer
            builder.yield(AnalyzerInput(buffer: converted))
        }
        builder.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        try await resultsTask.value

        let summary = await tracker.finish()
        let audioDuration = Duration.seconds(sampleRate > 0 ? frames / sampleRate : 0)
        emit(.completed(RecognitionMetrics(
            engine: choice.descriptor,
            audioDuration: audioDuration,
            wallClock: clock.now - start,
            firstResultLatency: summary.firstResultLatency,
            segmentCount: summary.segments
        )))
    }

    private func makeModules(_ module: Module, locale: Locale) -> [any SpeechModule] {
        switch module {
        case .transcriber:
            [SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults, .fastResults],
                attributeOptions: [.audioTimeRange]
            )]
        case .dictation:
            [DictationTranscriber(
                locale: locale,
                contentHints: [],
                transcriptionOptions: [.punctuation],
                reportingOptions: [.volatileResults],
                attributeOptions: [.audioTimeRange]
            )]
        }
    }

    private func ensureAssets(for modules: [any SpeechModule], progress: @escaping @Sendable (Double) -> Void) async throws {
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                let watcher = Task {
                    while !Task.isCancelled {
                        progress(request.progress.fractionCompleted)
                        try await Task.sleep(for: .milliseconds(250))
                    }
                }
                defer { watcher.cancel() }
                try await request.downloadAndInstall()
            }
            progress(1)
        } catch {
            throw RecognitionError.assetsUnavailable(error.localizedDescription)
        }
    }

    /// Collects results from the module's stream and forwards them as transcript updates.
    private actor ResultTracker {
        private let start: ContinuousClock.Instant
        private let clock: ContinuousClock
        private let emit: @Sendable (RecognitionUpdate) -> Void
        private var firstResultLatency: Duration?
        private var segments = 0

        init(start: ContinuousClock.Instant, clock: ContinuousClock, emit: @escaping @Sendable (RecognitionUpdate) -> Void) {
            self.start = start
            self.clock = clock
            self.emit = emit
        }

        func record(text: String, isFinal: Bool) {
            if firstResultLatency == nil, !text.isEmpty { firstResultLatency = clock.now - start }
            if isFinal {
                segments += 1
                emit(.finalized(text))
            } else {
                emit(.volatile(text))
            }
        }

        func finish() -> (firstResultLatency: Duration?, segments: Int) {
            (firstResultLatency, segments)
        }
    }

    nonisolated static func map(_ error: any Error) -> RecognitionError {
        if error is CancellationError { return .cancelled }
        if let known = error as? RecognitionError { return known }
        return .recognizer(error.localizedDescription)
    }
}
