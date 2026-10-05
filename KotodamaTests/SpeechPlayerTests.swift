//
//  SpeechPlayerTests.swift
//  KotodamaTests
//
//  Created by Kyle Zhao on 2026-10-06.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import AVFoundation
import Testing
@testable import Kotodama

struct SpeechPlayerTests {
    @Test func mapsLanguagesToVoiceTags() {
        #expect(LanguageOption.option(for: "yue-CN")?.voiceLanguage == "zh-HK")
        #expect(LanguageOption.option(for: "wuu-CN")?.voiceLanguage == "zh-CN")
        #expect(LanguageOption.option(for: "en-GB")?.voiceLanguage == "en-GB")
        #expect(TargetLanguage.target(for: "zh-Hant")?.voiceLanguage == "zh-TW")
        #expect(TargetLanguage.target(for: "ja")?.voiceLanguage == "ja-JP")
    }

    @MainActor @Test func findsVoicesForCoreLanguages() {
        for tag in ["en-US", "zh-CN", "ja-JP"] {
            let voice = SpeechPlayer.voice(for: tag)
            #expect(voice != nil, "voice for \(tag)")
            #expect(voice?.language.hasPrefix(String(tag.prefix(2))) == true)
        }
    }

    @MainActor @Test func catalogSortsBestQualityFirstAndDescribesVoices() {
        let voices = VoiceCatalog.voices(for: "en-US")
        #expect(!voices.isEmpty)
        for pair in zip(voices, voices.dropFirst()) {
            #expect(pair.0.quality.rawValue >= pair.1.quality.rawValue)
        }
        #expect(VoiceCatalog.describe(voices[0]).contains(voices[0].name))
        #expect(VoiceCatalog.qualityName(.premium) == "Premium")
        #expect(VoiceCatalog.sample(for: "ja-JP").contains("言霊"))
        #expect(VoiceCatalog.sample(for: "zh-TW").contains("言靈"))
    }

    @MainActor @Test func chosenVoiceOverridesTheDefault() {
        let defaults = UserDefaults(suiteName: "KotodamaTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults, keychain: KeychainStore(service: "com.kylezhao.Kotodama.tests"))
        let player = SpeechPlayer(settings: settings)
        let voices = VoiceCatalog.voices(for: "en-US")
        guard let last = voices.last else { return }
        settings.voiceIdentifiers["en-US"] = last.identifier
        #expect(player.resolvedVoice(for: "en-US")?.identifier == last.identifier)
        #expect(AppSettings(defaults: defaults, keychain: KeychainStore(service: "com.kylezhao.Kotodama.tests")).voiceIdentifiers["en-US"] == last.identifier)
    }

    @MainActor @Test func toggleTracksTheSpeakingSentence() {
        let player = SpeechPlayer()
        player.toggle("hello", id: "a", voiceLanguage: "en-US")
        #expect(player.isSpeaking("a"))
        player.toggle("hello", id: "a", voiceLanguage: "en-US")
        #expect(!player.isSpeaking("a"))
    }
}
