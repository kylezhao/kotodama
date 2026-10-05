//
//  LanguageOption.swift
//  Kotodama
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation

/// A spoken language or dialect the app can listen to.
struct LanguageOption: Identifiable, Hashable, Codable, Sendable {
    enum Group: String, Codable, CaseIterable, Sendable {
        case chinese, english, japanese, other

        var title: String {
            switch self {
            case .chinese: String(localized: "Chinese")
            case .english: String(localized: "English")
            case .japanese: String(localized: "Japanese")
            case .other: String(localized: "Other")
            }
        }
    }

    /// BCP 47 identifier, e.g. `zh-CN`, `yue-CN`, `en-US`.
    let id: String
    let name: String
    let nativeName: String
    let flag: String
    let group: Group
    /// True for regional varieties and dialects of a larger language.
    let isDialect: Bool

    var locale: Locale { Locale(identifier: id) }
    var language: Locale.Language { locale.language }

    static let recognitionCandidates: [LanguageOption] = [
        LanguageOption(id: "zh-CN", name: "Mandarin (China mainland)", nativeName: "普通话", flag: "🇨🇳", group: .chinese, isDialect: false),
        LanguageOption(id: "zh-TW", name: "Mandarin (Taiwan)", nativeName: "國語", flag: "🇹🇼", group: .chinese, isDialect: true),
        LanguageOption(id: "zh-HK", name: "Cantonese (Hong Kong)", nativeName: "廣東話", flag: "🇭🇰", group: .chinese, isDialect: true),
        LanguageOption(id: "yue-CN", name: "Cantonese (China mainland)", nativeName: "粤语", flag: "🇨🇳", group: .chinese, isDialect: true),
        LanguageOption(id: "wuu-CN", name: "Shanghainese", nativeName: "上海话", flag: "🇨🇳", group: .chinese, isDialect: true),
        LanguageOption(id: "en-US", name: "English (United States)", nativeName: "English", flag: "🇺🇸", group: .english, isDialect: false),
        LanguageOption(id: "en-GB", name: "English (United Kingdom)", nativeName: "English", flag: "🇬🇧", group: .english, isDialect: true),
        LanguageOption(id: "en-AU", name: "English (Australia)", nativeName: "English", flag: "🇦🇺", group: .english, isDialect: true),
        LanguageOption(id: "en-IN", name: "English (India)", nativeName: "English", flag: "🇮🇳", group: .english, isDialect: true),
        LanguageOption(id: "en-SG", name: "English (Singapore)", nativeName: "English", flag: "🇸🇬", group: .english, isDialect: true),
        LanguageOption(id: "ja-JP", name: "Japanese", nativeName: "日本語", flag: "🇯🇵", group: .japanese, isDialect: false),
        LanguageOption(id: "ko-KR", name: "Korean", nativeName: "한국어", flag: "🇰🇷", group: .other, isDialect: false),
        LanguageOption(id: "es-ES", name: "Spanish", nativeName: "Español", flag: "🇪🇸", group: .other, isDialect: false),
        LanguageOption(id: "fr-FR", name: "French", nativeName: "Français", flag: "🇫🇷", group: .other, isDialect: false),
        LanguageOption(id: "de-DE", name: "German", nativeName: "Deutsch", flag: "🇩🇪", group: .other, isDialect: false),
    ]

    static let `default` = recognitionCandidates.first { $0.id == "en-US" }!

    static func option(for id: String) -> LanguageOption? {
        recognitionCandidates.first { $0.id == id }
    }

    /// Best matching option for a device locale, falling back to English.
    static func matching(_ locale: Locale) -> LanguageOption {
        let wanted = locale.identifier(.bcp47)
        if let exact = recognitionCandidates.first(where: { $0.id == wanted }) { return exact }
        if let code = locale.language.languageCode?.identifier,
           let sameLanguage = recognitionCandidates.first(where: { $0.language.languageCode?.identifier == code }) {
            return sameLanguage
        }
        return .default
    }
}

/// A language the app can translate into.
struct TargetLanguage: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let nativeName: String
    let flag: String

    var language: Locale.Language { Locale.Language(identifier: id) }

    static let all: [TargetLanguage] = [
        TargetLanguage(id: "en", name: "English", nativeName: "English", flag: "🇺🇸"),
        TargetLanguage(id: "zh-Hans", name: "Chinese (Simplified)", nativeName: "简体中文", flag: "🇨🇳"),
        TargetLanguage(id: "zh-Hant", name: "Chinese (Traditional)", nativeName: "繁體中文", flag: "🇹🇼"),
        TargetLanguage(id: "ja", name: "Japanese", nativeName: "日本語", flag: "🇯🇵"),
        TargetLanguage(id: "ko", name: "Korean", nativeName: "한국어", flag: "🇰🇷"),
        TargetLanguage(id: "es", name: "Spanish", nativeName: "Español", flag: "🇪🇸"),
        TargetLanguage(id: "fr", name: "French", nativeName: "Français", flag: "🇫🇷"),
        TargetLanguage(id: "de", name: "German", nativeName: "Deutsch", flag: "🇩🇪"),
    ]

    static let defaultSelection: [String] = ["en", "zh-Hans", "ja"]

    static func target(for id: String) -> TargetLanguage? {
        all.first { $0.id == id }
    }

    /// True when the target is the same language as the spoken one, so translating would be a no-op.
    func matches(_ source: LanguageOption) -> Bool {
        let sourceCode = source.language.languageCode?.identifier ?? ""
        let targetCode = language.languageCode?.identifier ?? ""
        guard sourceCode == targetCode else {
            // Treat Cantonese and Shanghainese as Chinese for translation purposes.
            let chineseCodes: Set<String> = ["zh", "yue", "wuu"]
            if chineseCodes.contains(sourceCode), targetCode == "zh" {
                return matchesChineseScript(of: source)
            }
            return false
        }
        if targetCode == "zh" { return matchesChineseScript(of: source) }
        return true
    }

    private func matchesChineseScript(of source: LanguageOption) -> Bool {
        let traditionalRegions: Set<String> = ["TW", "HK", "MO"]
        let sourceIsTraditional = traditionalRegions.contains(source.locale.region?.identifier ?? "")
        return (id == "zh-Hant") == sourceIsTraditional
    }
}
