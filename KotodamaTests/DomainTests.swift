//
//  DomainTests.swift
//  KotodamaTests
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import AVFAudio
import Foundation
import Testing
@testable import Kotodama

struct LanguageTests {
    @Test func matchesDeviceLocaleToACandidate() {
        #expect(LanguageOption.matching(Locale(identifier: "zh_CN")).id == "zh-CN")
        #expect(LanguageOption.matching(Locale(identifier: "en_CA")).id == "en-US")
        #expect(LanguageOption.matching(Locale(identifier: "ja_JP")).id == "ja-JP")
        #expect(LanguageOption.matching(Locale(identifier: "sw_KE")).id == "en-US")
    }

    @Test func chineseDialectsAreMarked() {
        let cantonese = LanguageOption.option(for: "zh-HK")!
        #expect(cantonese.isDialect)
        #expect(cantonese.group == .chinese)
        #expect(LanguageOption.recognitionCandidates.filter { $0.group == .chinese && $0.isDialect }.count >= 3)
    }

    @Test func targetsSkipTheSpokenLanguage() {
        let english = TargetLanguage.target(for: "en")!
        let simplified = TargetLanguage.target(for: "zh-Hans")!
        let traditional = TargetLanguage.target(for: "zh-Hant")!
        #expect(english.matches(LanguageOption.option(for: "en-GB")!))
        #expect(!english.matches(LanguageOption.option(for: "ja-JP")!))
        #expect(simplified.matches(LanguageOption.option(for: "zh-CN")!))
        #expect(!simplified.matches(LanguageOption.option(for: "zh-TW")!))
        #expect(traditional.matches(LanguageOption.option(for: "zh-HK")!))
        #expect(simplified.matches(LanguageOption.option(for: "yue-CN")!))
    }

    @Test func makesTitles() {
        #expect(Transcript.makeTitle(from: "hello there this is a long sentence about things") == "hello there this is a long…")
        #expect(Transcript.makeTitle(from: "short") == "short")
        #expect(Transcript.makeTitle(from: "这是一个很长很长很长很长的中文句子用来测试") == "这是一个很长很长很长很长的中…")
        #expect(Transcript.makeTitle(from: "   ") == "Untitled")
    }
}

struct AudioTests {
    @Test func convertsStereo48kToMono16k() throws {
        let input = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 4_800)!
        buffer.frameLength = 4_800
        for frame in 0..<4_800 {
            let sample = Float(sin(Double(frame) / 48_000 * 2 * .pi * 440))
            buffer.floatChannelData![0][frame] = sample
            buffer.floatChannelData![1][frame] = sample
        }
        var converter = BufferConverter()
        let converted = try converter.convert(buffer, to: output)
        #expect(converted.format.sampleRate == 16_000)
        #expect(converted.format.channelCount == 1)
        #expect(abs(Int(converted.frameLength) - 1_600) <= 2)
    }

    @Test func rmsLevelTracksAmplitude() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let silent = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
        silent.frameLength = 1_600
        let loud = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
        loud.frameLength = 1_600
        for frame in 0..<1_600 { loud.floatChannelData![0][frame] = frame.isMultiple(of: 2) ? 0.9 : -0.9 }
        #expect(silent.rmsLevel == 0)
        #expect(loud.rmsLevel > 0.9)
    }

    @Test func readsBundledSampleAsBuffers() async throws {
        let url = try #require(Bundle.main.url(forResource: "sample-en-US", withExtension: "wav"))
        let source = try AudioFileReader.open(url, chunkFrames: 8_000)
        #expect(source.duration > 4 && source.duration < 6)
        var frames = 0
        var buffers = 0
        for await buffer in source.stream {
            frames += Int(buffer.frameLength)
            buffers += 1
        }
        #expect(buffers >= 9)
        #expect(abs(Double(frames) / source.format.sampleRate - source.duration) < 0.01)
    }

    @Test func clonedBufferMatchesOriginal() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 100)!
        buffer.frameLength = 100
        for frame in 0..<100 { buffer.floatChannelData![0][frame] = Float(frame) / 100 }
        let copy = buffer.cloned()!
        #expect(copy.frameLength == 100)
        #expect(copy.floatChannelData![0][42] == buffer.floatChannelData![0][42])
    }
}

/// Exercises the real on-device recognizer when the simulator or device supports it.
/// Returns early (passing vacuously) when the module is unavailable, and prints why.
struct OnDeviceRecognitionTests {
    @Test(.timeLimit(.minutes(4))) func transcribesEnglishSampleOnDevice() async throws {
        let recognizer = AppleOnDeviceRecognizer()
        let english = LanguageOption.option(for: "en-US")!
        let availability = await recognizer.availability(for: english)
        if case .unavailable(let reason) = availability {
            print("Skipping on-device recognition test: \(reason)")
            return
        }
        try await recognizer.prepare(language: english) { _ in }
        let url = try #require(Bundle.main.url(forResource: "sample-en-US", withExtension: "wav"))
        let source = try AudioFileReader.open(url)
        var finalized: [String] = []
        var metrics: RecognitionMetrics?
        for try await update in recognizer.transcribe(source.stream, language: english) {
            switch update {
            case .finalized(let text): finalized.append(text)
            case .completed(let result): metrics = result
            case .volatile: break
            }
        }
        let text = finalized.joined(separator: " ").lowercased()
        print("On-device transcript: \(text)")
        #expect(text.contains("test"))
        #expect(text.contains("transcribe") || text.contains("sentence"))
        let result = try #require(metrics)
        #expect(result.audioSeconds > 4)
        #expect(result.engine.mode == .onDevice)
    }
}
