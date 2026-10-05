//
//  SpeakViewModel.swift
//  Kotodama
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import AVFAudio
import Foundation
import Observation
import SwiftData

/// Drives one utterance end to end: capture → recognition → polishing → translation → history.
@MainActor
@Observable
final class SpeakViewModel {
    enum Phase: Equatable {
        case idle
        case preparing(Double)
        case listening
        case transcribingFile
        case refining
        case translating
        case done
    }

    let settings: AppSettings
    let capture = AudioCapture()
    private let modelContext: ModelContext
    private let translationCoordinator: AppleTranslationCoordinator
    private let onDeviceRecognizer = AppleOnDeviceRecognizer()
    private let cloudRecognizer = AppleCloudRecognizer()

    private(set) var phase: Phase = .idle
    private(set) var finalizedText = ""
    private(set) var volatileText = ""
    private(set) var recognitionMetrics: RecognitionMetrics?
    private(set) var refined: RefinedText?
    private(set) var skippedRefiners: [String] = []
    private(set) var translations: [TranslationOutput] = []
    private(set) var translationErrors: [String] = []
    private(set) var savedTranscript: Transcript?
    private(set) var availability: RecognizerAvailability = .ready
    private(set) var activeDescriptor: RecognizerDescriptor?
    var errorMessage: String?

    private var recognitionTask: Task<Void, Never>?

    init(settings: AppSettings, modelContext: ModelContext, translationCoordinator: AppleTranslationCoordinator) {
        self.settings = settings
        self.modelContext = modelContext
        self.translationCoordinator = translationCoordinator
    }

    // MARK: - Derived state

    var language: LanguageOption { settings.sourceLanguage }
    var recognizer: any SpeechRecognizer { settings.recognitionMode == .onDevice ? onDeviceRecognizer : cloudRecognizer }
    var isListening: Bool { phase == .listening }
    var isBusy: Bool {
        switch phase {
        case .idle, .done: false
        default: true
        }
    }

    /// Finalized segments plus the in-progress text, joined with the right separator for the language.
    var liveText: String {
        guard !volatileText.isEmpty else { return finalizedText }
        guard !finalizedText.isEmpty else { return volatileText }
        return finalizedText + separator + volatileText
    }

    private var separator: String {
        language.group == .chinese || language.group == .japanese || language.id.hasPrefix("ko") ? "" : " "
    }

    var statusLine: String {
        switch phase {
        case .idle: String(localized: "Tap the orb and speak")
        case .preparing(let progress): String(localized: "Downloading speech model… \(Int(progress * 100))%")
        case .listening: String(localized: "Listening…")
        case .transcribingFile: String(localized: "Transcribing audio…")
        case .refining: String(localized: "Refining the words…")
        case .translating: String(localized: "Carrying the words across…")
        case .done: String(localized: "Done")
        }
    }

    // MARK: - Availability

    func refreshAvailability() async {
        availability = await recognizer.availability(for: language)
        activeDescriptor = await recognizer.descriptor(for: language)
    }

    func downloadModel() async {
        phase = .preparing(0)
        do {
            try await recognizer.prepare(language: language) { [weak self] progress in
                Task { @MainActor in
                    if case .preparing = self?.phase { self?.phase = .preparing(progress) }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        phase = .idle
        await refreshAvailability()
    }

    // MARK: - Microphone

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            Task { await startListening() }
        }
    }

    func startListening() async {
        guard !isBusy else { return }
        resetOutputs()
        errorMessage = nil

        guard await capture.requestPermission() else {
            errorMessage = RecognitionError.microphoneDenied.localizedDescription
            return
        }
        if case .needsDownload = availability {
            await downloadModel()
            guard case .ready = availability else { return }
        }
        if settings.recognitionMode == .cloud {
            do { try await AppleCloudRecognizer.authorize() } catch {
                errorMessage = error.localizedDescription
                return
            }
        }

        let audio: AsyncStream<AVAudioPCMBuffer>
        do {
            audio = try capture.start()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        phase = .listening
        recognitionTask = Task { await runRecognition(audio: audio, language: language) }
    }

    func stopListening() {
        guard isListening else { return }
        capture.stop()
        // The recognition task finishes on its own once the audio stream ends.
    }

    func cancel() {
        capture.stop()
        recognitionTask?.cancel()
        recognitionTask = nil
        phase = .idle
    }

    // MARK: - Files and samples

    func transcribe(fileURL: URL, language override: LanguageOption? = nil) {
        guard !isBusy else { return }
        resetOutputs()
        errorMessage = nil
        if let override { settings.sourceLanguageID = override.id }
        let language = self.language
        do {
            let source = try AudioFileReader.open(fileURL)
            phase = .transcribingFile
            recognitionTask = Task { await runRecognition(audio: source.stream, language: language) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static let sampleLanguages: [LanguageOption] = ["en-US", "zh-CN", "ja-JP"].compactMap(LanguageOption.option(for:))

    func transcribeSample(_ language: LanguageOption) {
        guard let url = Bundle.main.url(forResource: "sample-\(language.id)", withExtension: "wav") else {
            errorMessage = String(localized: "Sample audio for \(language.name) is missing.")
            return
        }
        transcribe(fileURL: url, language: language)
    }

    // MARK: - Pipeline

    private func runRecognition(audio: AsyncStream<AVAudioPCMBuffer>, language: LanguageOption) async {
        var metrics: RecognitionMetrics?
        do {
            if case .needsDownload = await recognizer.availability(for: language) {
                phase = .preparing(0)
                try await recognizer.prepare(language: language) { [weak self] progress in
                    Task { @MainActor in
                        if case .preparing = self?.phase { self?.phase = .preparing(progress) }
                    }
                }
                phase = capture.isRunning ? .listening : .transcribingFile
            }
            for try await update in recognizer.transcribe(audio, language: language) {
                switch update {
                case .volatile(let text):
                    volatileText = text
                case .finalized(let text):
                    volatileText = ""
                    finalizedText = finalizedText.isEmpty ? text : finalizedText + separator + text
                case .completed(let result):
                    metrics = result
                }
            }
        } catch {
            capture.stop()
            let message = (error as? RecognitionError)?.localizedDescription ?? error.localizedDescription
            if (error as? RecognitionError) != .cancelled { errorMessage = message }
            phase = finalizedText.isEmpty ? .idle : .done
            if !finalizedText.isEmpty { await postProcess(rawText: finalizedText, language: language, metrics: metrics) }
            return
        }
        capture.stop()

        // Keep any trailing volatile text the engine never finalized.
        if !volatileText.isEmpty {
            finalizedText = finalizedText.isEmpty ? volatileText : finalizedText + separator + volatileText
            volatileText = ""
        }
        recognitionMetrics = metrics
        guard !finalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = RecognitionError.noSpeechDetected.localizedDescription
            phase = .idle
            return
        }
        await postProcess(rawText: finalizedText, language: language, metrics: metrics)
    }

    private func postProcess(rawText: String, language: LanguageOption, metrics: RecognitionMetrics?) async {
        phase = .refining
        let pipeline = RefinementPipeline(
            mode: settings.intelligenceMode,
            onDevice: OnDeviceTextRefiner(),
            cloud: CloudTextRefiner(client: settings.claudeClient)
        )
        let request = RefinementRequest(text: rawText, language: language, style: settings.style, scenario: settings.scenario)
        let (result, skipped) = await pipeline.refine(request)
        refined = result
        skippedRefiners = skipped

        let descriptor = metrics?.engine ?? activeDescriptor ?? RecognizerDescriptor(mode: settings.recognitionMode, displayName: "Apple Speech", modelID: "unknown")
        let transcript = Transcript(
            languageID: language.id,
            rawText: rawText,
            style: settings.style,
            scenario: settings.scenario,
            recognitionMode: settings.recognitionMode,
            recognizerName: descriptor.displayName,
            recognizerModelID: descriptor.modelID,
            audioDuration: metrics?.audioSeconds ?? 0,
            recognitionSeconds: metrics?.wallClockSeconds ?? 0,
            firstResultSeconds: metrics?.firstResultLatency?.seconds
        )
        transcript.polishedText = result.text
        transcript.title = result.title.isEmpty ? Transcript.makeTitle(from: result.text) : result.title
        transcript.summary = result.summary
        transcript.refinerName = result.engine.displayName
        transcript.refinerModelID = result.engine.modelID
        transcript.refinementSeconds = result.latency.seconds
        modelContext.insert(transcript)
        savedTranscript = transcript
        save()

        if settings.autoTranslate {
            phase = .translating
            await translate(transcript, text: result.text, language: language)
        }
        phase = .done
    }

    func translate(_ transcript: Transcript, text: String, language: LanguageOption) async {
        translations = []
        translationErrors = []
        let pipeline = TranslationPipeline(
            mode: settings.intelligenceMode,
            apple: AppleTranslator(coordinator: translationCoordinator),
            cloud: CloudTranslator(client: settings.claudeClient)
        )
        for target in settings.targetLanguages where !target.matches(language) {
            do {
                let output = try await pipeline.translate(text, from: language, to: target)
                translations.append(output)
                let record = TranslationResult(
                    targetLanguageID: target.id,
                    text: output.text,
                    translatorName: output.engine.displayName,
                    translatorModelID: output.engine.modelID,
                    seconds: output.latency.seconds,
                    transcript: transcript
                )
                modelContext.insert(record)
                transcript.translations.append(record)
            } catch {
                translationErrors.append("\(target.flag) \(target.name): \(error.localizedDescription)")
            }
        }
        save()
    }

    /// Re-polishes the last result with the current style and scenario.
    func repolish() async {
        guard let transcript = savedTranscript, !isBusy else { return }
        phase = .refining
        let pipeline = RefinementPipeline(mode: settings.intelligenceMode, onDevice: OnDeviceTextRefiner(), cloud: CloudTextRefiner(client: settings.claudeClient))
        let request = RefinementRequest(text: transcript.rawText, language: transcript.language, style: settings.style, scenario: settings.scenario)
        let (result, skipped) = await pipeline.refine(request)
        refined = result
        skippedRefiners = skipped
        transcript.polishedText = result.text
        transcript.styleRaw = settings.style.rawValue
        transcript.scenarioRaw = settings.scenario.rawValue
        transcript.refinerName = result.engine.displayName
        transcript.refinerModelID = result.engine.modelID
        transcript.refinementSeconds = result.latency.seconds
        for old in transcript.translations { modelContext.delete(old) }
        transcript.translations.removeAll()
        save()
        if settings.autoTranslate {
            phase = .translating
            await translate(transcript, text: result.text, language: transcript.language)
        }
        phase = .done
    }

    func resetOutputs() {
        finalizedText = ""
        volatileText = ""
        recognitionMetrics = nil
        refined = nil
        skippedRefiners = []
        translations = []
        translationErrors = []
        savedTranscript = nil
        phase = .idle
    }

    private func save() {
        do { try modelContext.save() } catch { assertionFailure("Save failed: \(error)") }
    }
}
