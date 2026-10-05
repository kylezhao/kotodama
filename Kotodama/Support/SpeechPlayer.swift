//
//  SpeechPlayer.swift
//  Kotodama
//
//  Created by Kyle Zhao on 2026-10-06.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import AVFoundation
import Foundation
import Observation

/// Reads sentences aloud with the system voices. One utterance plays at a time; tapping the same
/// sentence again stops it.
@MainActor
@Observable
final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    /// Identifier of the sentence currently being spoken, for the play/stop button state.
    private(set) var speakingID: String?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func isSpeaking(_ id: String) -> Bool { speakingID == id }

    func toggle(_ text: String, id: String, voiceLanguage: String) {
        if speakingID == id {
            stop()
            return
        }
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(for: voiceLanguage)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speakingID = id
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        speakingID = nil
    }

    /// Best available voice for a BCP 47 language, preferring enhanced or premium quality.
    static func voice(for language: String) -> AVSpeechSynthesisVoice? {
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased() == language.lowercased() }
        if let best = candidates.max(by: { $0.quality.rawValue < $1.quality.rawValue }) { return best }
        if let prefix = language.split(separator: "-").first {
            let sameLanguage = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix(prefix.lowercased() + "-") }
            if let best = sameLanguage.max(by: { $0.quality.rawValue < $1.quality.rawValue }) { return best }
        }
        return AVSpeechSynthesisVoice(language: language)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speakingID = nil }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speakingID = nil }
    }
}

extension LanguageOption {
    /// Language tag for the speech synthesizer. Dialects without their own voice map to the closest one.
    var voiceLanguage: String {
        switch id {
        case "yue-CN": "zh-HK"
        case "wuu-CN": "zh-CN"
        default: id
        }
    }
}

extension TargetLanguage {
    var voiceLanguage: String {
        switch id {
        case "en": "en-US"
        case "zh-Hans": "zh-CN"
        case "zh-Hant": "zh-TW"
        case "ja": "ja-JP"
        case "ko": "ko-KR"
        case "es": "es-ES"
        case "fr": "fr-FR"
        case "de": "de-DE"
        default: id
        }
    }
}
