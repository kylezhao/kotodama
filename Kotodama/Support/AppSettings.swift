//
//  AppSettings.swift
//  Kotodama
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import Observation

/// Which model family polishes and translates text.
enum IntelligenceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// On-device models first, cloud if configured, rules as the last resort.
    case automatic
    case onDevice
    case cloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: String(localized: "Automatic")
        case .onDevice: String(localized: "On-device")
        case .cloud: String(localized: "Cloud")
        }
    }
}

/// User preferences. Small values live in UserDefaults; the API key lives in the keychain.
@MainActor
@Observable
final class AppSettings {
    private enum Keys {
        static let recognitionMode = "recognitionMode"
        static let intelligenceMode = "intelligenceMode"
        static let sourceLanguage = "sourceLanguage"
        static let targetLanguages = "targetLanguages"
        static let style = "style"
        static let scenario = "scenario"
        static let cloudModel = "cloudModel"
        static let showMetrics = "showMetrics"
        static let autoTranslate = "autoTranslate"
        static let apiKeyAccount = "anthropic-api-key"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    var recognitionMode: RecognitionMode { didSet { defaults.set(recognitionMode.rawValue, forKey: Keys.recognitionMode) } }
    var intelligenceMode: IntelligenceMode { didSet { defaults.set(intelligenceMode.rawValue, forKey: Keys.intelligenceMode) } }
    var sourceLanguageID: String { didSet { defaults.set(sourceLanguageID, forKey: Keys.sourceLanguage) } }
    var targetLanguageIDs: [String] { didSet { defaults.set(targetLanguageIDs, forKey: Keys.targetLanguages) } }
    var style: SpeakingStyle { didSet { defaults.set(style.rawValue, forKey: Keys.style) } }
    var scenario: UsageScenario { didSet { defaults.set(scenario.rawValue, forKey: Keys.scenario) } }
    var cloudModel: CloudModel { didSet { defaults.set(cloudModel.rawValue, forKey: Keys.cloudModel) } }
    var showMetrics: Bool { didSet { defaults.set(showMetrics, forKey: Keys.showMetrics) } }
    var autoTranslate: Bool { didSet { defaults.set(autoTranslate, forKey: Keys.autoTranslate) } }
    var apiKey: String { didSet { keychain.set(apiKey, for: Keys.apiKeyAccount) } }

    var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var sourceLanguage: LanguageOption { LanguageOption.option(for: sourceLanguageID) ?? .default }
    var targetLanguages: [TargetLanguage] { targetLanguageIDs.compactMap(TargetLanguage.target(for:)) }

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = .shared) {
        self.defaults = defaults
        self.keychain = keychain
        recognitionMode = defaults.string(forKey: Keys.recognitionMode).flatMap(RecognitionMode.init(rawValue:)) ?? .onDevice
        intelligenceMode = defaults.string(forKey: Keys.intelligenceMode).flatMap(IntelligenceMode.init(rawValue:)) ?? .automatic
        sourceLanguageID = defaults.string(forKey: Keys.sourceLanguage) ?? LanguageOption.matching(.current).id
        targetLanguageIDs = defaults.stringArray(forKey: Keys.targetLanguages) ?? TargetLanguage.defaultSelection
        style = defaults.string(forKey: Keys.style).flatMap(SpeakingStyle.init(rawValue:)) ?? .natural
        scenario = defaults.string(forKey: Keys.scenario).flatMap(UsageScenario.init(rawValue:)) ?? .notes
        cloudModel = defaults.string(forKey: Keys.cloudModel).flatMap(CloudModel.init(rawValue:)) ?? .default
        showMetrics = defaults.object(forKey: Keys.showMetrics) as? Bool ?? true
        autoTranslate = defaults.object(forKey: Keys.autoTranslate) as? Bool ?? true
        apiKey = keychain.string(for: Keys.apiKeyAccount) ?? ""
    }

    func toggleTarget(_ target: TargetLanguage) {
        if let index = targetLanguageIDs.firstIndex(of: target.id) {
            targetLanguageIDs.remove(at: index)
        } else {
            targetLanguageIDs.append(target.id)
        }
    }

    var claudeClient: ClaudeClient { ClaudeClient(apiKey: apiKey, model: cloudModel) }
}
