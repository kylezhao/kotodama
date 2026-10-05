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

    @MainActor @Test func toggleTracksTheSpeakingSentence() {
        let player = SpeechPlayer()
        player.toggle("hello", id: "a", voiceLanguage: "en-US")
        #expect(player.isSpeaking("a"))
        player.toggle("hello", id: "a", voiceLanguage: "en-US")
        #expect(!player.isSpeaking("a"))
    }
}
