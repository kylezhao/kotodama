//
//  SpeechRecognizer.swift
//  Kotodama
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import AVFAudio
import Foundation

/// Where speech recognition runs.
enum RecognitionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Apple's speech models running on this device. Works offline.
    case onDevice
    /// Apple's speech servers through `SFSpeechRecognizer`. Needs network.
    case cloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onDevice: String(localized: "On-device")
        case .cloud: String(localized: "Cloud")
        }
    }

    var subtitle: String {
        switch self {
        case .onDevice: String(localized: "Apple speech models on this device · works offline")
        case .cloud: String(localized: "Apple's speech servers · needs network")
        }
    }

    var symbol: String {
        switch self {
        case .onDevice: "iphone.gen3"
        case .cloud: "cloud.fill"
        }
    }
}

struct RecognizerDescriptor: Hashable, Sendable {
    let mode: RecognitionMode
    let displayName: String
    let modelID: String
}

enum RecognizerAvailability: Equatable, Sendable {
    case ready
    case needsDownload
    case unavailable(reason: String)
}

enum RecognitionUpdate: Sendable {
    /// In-progress text for the current segment. Replaces the previous volatile text.
    case volatile(String)
    /// A finished segment to append to the transcript.
    case finalized(String)
    case completed(RecognitionMetrics)
}

struct RecognitionMetrics: Equatable, Sendable {
    var engine: RecognizerDescriptor
    var audioDuration: Duration
    var wallClock: Duration
    var firstResultLatency: Duration?
    var segmentCount: Int

    var audioSeconds: Double { audioDuration.seconds }
    var wallClockSeconds: Double { wallClock.seconds }
    /// Below 1.0 means recognition kept up with the audio.
    var realTimeFactor: Double { audioSeconds > 0 ? wallClockSeconds / audioSeconds : 0 }
}

/// A speech-to-text backend. Audio arrives as PCM buffers from the microphone or a file; the
/// recognizer finalizes when the stream ends.
protocol SpeechRecognizer: Sendable {
    var mode: RecognitionMode { get }
    func descriptor(for language: LanguageOption) async -> RecognizerDescriptor
    func availability(for language: LanguageOption) async -> RecognizerAvailability
    /// Requests permissions and downloads language assets when needed.
    func prepare(language: LanguageOption, progress: @escaping @Sendable (Double) -> Void) async throws
    func transcribe(_ audio: AsyncStream<AVAudioPCMBuffer>, language: LanguageOption) -> AsyncThrowingStream<RecognitionUpdate, any Error>
}

enum RecognitionError: LocalizedError, Equatable, Sendable {
    case unsupportedLanguage(String)
    case assetsUnavailable(String)
    case microphoneDenied
    case speechRecognitionDenied
    case audioEngine(String)
    case recognizer(String)
    case noSpeechDetected
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unsupportedLanguage(let name): String(localized: "\(name) is not supported by this engine. Try the other mode.")
        case .assetsUnavailable(let detail): String(localized: "The speech model could not be downloaded.") + " " + detail
        case .microphoneDenied: String(localized: "Microphone access is off. Allow it in Settings to speak.")
        case .speechRecognitionDenied: String(localized: "Speech recognition access is off. Allow it in Settings.")
        case .audioEngine(let detail): String(localized: "The microphone could not start.") + " " + detail
        case .recognizer(let detail): detail
        case .noSpeechDetected: String(localized: "No words were heard. Try speaking a little louder.")
        case .cancelled: String(localized: "Cancelled.")
        }
    }
}

extension Duration {
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
