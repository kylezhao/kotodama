//
//  Transcript.swift
//  Kotodama
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import SwiftData

/// One recorded utterance with its raw transcription, polished text, translations and metrics.
@Model
final class Transcript {
    var id: UUID
    var createdAt: Date
    var title: String
    var languageID: String
    var rawText: String
    var polishedText: String
    var styleRaw: String
    var scenarioRaw: String

    // Recognition metrics
    var recognitionModeRaw: String
    var recognizerName: String
    var recognizerModelID: String
    var audioDuration: Double
    var recognitionSeconds: Double
    var firstResultSeconds: Double?

    // Refinement metrics
    var refinerName: String?
    var refinerModelID: String?
    var refinementSeconds: Double?
    var summary: String?

    @Relationship(deleteRule: .cascade, inverse: \TranslationResult.transcript)
    var translations: [TranslationResult] = []

    init(
        languageID: String,
        rawText: String,
        style: SpeakingStyle,
        scenario: UsageScenario,
        recognitionMode: RecognitionMode,
        recognizerName: String,
        recognizerModelID: String,
        audioDuration: Double,
        recognitionSeconds: Double,
        firstResultSeconds: Double?
    ) {
        self.id = UUID()
        self.createdAt = .now
        self.title = Transcript.makeTitle(from: rawText)
        self.languageID = languageID
        self.rawText = rawText
        self.polishedText = rawText
        self.styleRaw = style.rawValue
        self.scenarioRaw = scenario.rawValue
        self.recognitionModeRaw = recognitionMode.rawValue
        self.recognizerName = recognizerName
        self.recognizerModelID = recognizerModelID
        self.audioDuration = audioDuration
        self.recognitionSeconds = recognitionSeconds
        self.firstResultSeconds = firstResultSeconds
    }

    var language: LanguageOption { LanguageOption.option(for: languageID) ?? .default }
    var style: SpeakingStyle { SpeakingStyle(rawValue: styleRaw) ?? .natural }
    var scenario: UsageScenario { UsageScenario(rawValue: scenarioRaw) ?? .notes }
    var recognitionMode: RecognitionMode { RecognitionMode(rawValue: recognitionModeRaw) ?? .onDevice }

    var sortedTranslations: [TranslationResult] {
        translations.sorted { $0.createdAt < $1.createdAt }
    }

    static func makeTitle(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return String(localized: "Untitled") }
        let words = trimmed.split(separator: " ")
        if words.count > 1 {
            let head = words.prefix(6).joined(separator: " ")
            return head.count < trimmed.count ? head + "…" : head
        }
        // Languages without spaces: take the first characters.
        return trimmed.count > 14 ? String(trimmed.prefix(14)) + "…" : trimmed
    }
}

/// A translation of a transcript into one target language.
@Model
final class TranslationResult {
    var id: UUID
    var createdAt: Date
    var targetLanguageID: String
    var text: String
    var translatorName: String
    var translatorModelID: String
    var seconds: Double

    var transcript: Transcript?

    init(targetLanguageID: String, text: String, translatorName: String, translatorModelID: String, seconds: Double, transcript: Transcript) {
        self.id = UUID()
        self.createdAt = .now
        self.targetLanguageID = targetLanguageID
        self.text = text
        self.translatorName = translatorName
        self.translatorModelID = translatorModelID
        self.seconds = seconds
        self.transcript = transcript
    }

    var target: TargetLanguage? { TargetLanguage.target(for: targetLanguageID) }
}
