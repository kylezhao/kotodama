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
    private let settings: AppSettings?
    /// Identifier of the sentence currently being spoken, for the play/stop button state.
    private(set) var speakingID: String?
    /// Name and quality of the voice in use, e.g. "Kyoko · Enhanced".
    private(set) var speakingVoiceDescription = ""

    init(settings: AppSettings? = nil) {
        self.settings = settings
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
        let voice = resolvedVoice(for: voiceLanguage)
        utterance.voice = voice
        // Chinese, Japanese and Korean read more naturally a touch slower than the default pace.
        let cjk = ["zh", "ja", "ko"].contains(String(voiceLanguage.prefix(2)))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (cjk ? 0.9 : 1.0)
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        speakingVoiceDescription = voice.map(VoiceCatalog.describe) ?? ""
        speakingID = id
        synthesizer.speak(utterance)
    }

    /// The user's chosen voice for the language, else the best installed one.
    func resolvedVoice(for language: String) -> AVSpeechSynthesisVoice? {
        if let identifier = settings?.voiceIdentifiers[language], let chosen = AVSpeechSynthesisVoice(identifier: identifier) {
            return chosen
        }
        return Self.voice(for: language)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        speakingID = nil
    }

    /// Plays a short sample sentence in the language, for the voice picker.
    func preview(language: String) {
        toggle(VoiceCatalog.sample(for: language), id: "preview-\(language)", voiceLanguage: language)
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


/// Installed synthesizer voices and how to describe them.
enum VoiceCatalog {
    /// Voices for a BCP 47 tag, best quality first. Falls back to voices sharing the language code.
    static func voices(for language: String) -> [AVSpeechSynthesisVoice] {
        let all = AVSpeechSynthesisVoice.speechVoices()
        var matches = all.filter { $0.language.lowercased() == language.lowercased() }
        if matches.isEmpty, let code = language.split(separator: "-").first {
            matches = all.filter { $0.language.lowercased().hasPrefix(code.lowercased() + "-") }
        }
        return matches.sorted {
            if $0.quality != $1.quality { return $0.quality.rawValue > $1.quality.rawValue }
            return $0.name < $1.name
        }
    }

    static func qualityName(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: String(localized: "Premium")
        case .enhanced: String(localized: "Enhanced")
        default: String(localized: "Default")
        }
    }

    static func describe(_ voice: AVSpeechSynthesisVoice) -> String {
        "\(voice.name) · \(qualityName(voice.quality))"
    }

    /// True when a better-than-default voice could be downloaded for the language.
    static func hasOnlyDefaultVoices(for language: String) -> Bool {
        let voices = voices(for: language)
        return !voices.isEmpty && voices.allSatisfy { $0.quality == .default }
    }

    static func sample(for language: String) -> String {
        switch String(language.prefix(2)) {
        case "zh": language.lowercased().hasSuffix("tw") || language.lowercased().hasSuffix("hk") ? "言靈，寄宿在話語中的靈。" : "言灵，寄宿在话语中的灵。"
        case "ja": "言霊、言葉に宿る魂。"
        case "ko": "말에 깃든 영혼, 고토다마."
        case "es": "El espíritu que vive en las palabras."
        case "fr": "L'esprit qui habite les mots."
        case "de": "Der Geist, der in den Worten wohnt."
        default: "Kotodama, the spirit that dwells in words."
        }
    }
}
