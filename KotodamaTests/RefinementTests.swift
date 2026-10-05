//
//  RefinementTests.swift
//  KotodamaTests
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import Testing
@testable import Kotodama

struct RuleBasedRefinerTests {
    private let english = LanguageOption.option(for: "en-US")!
    private let mandarin = LanguageOption.option(for: "zh-CN")!
    private let japanese = LanguageOption.option(for: "ja-JP")!

    @Test func removesFillersAndRepeatsInEnglish() {
        let polished = RuleBasedTextRefiner.polish("um so I I think we should, uh, ship it tomorrow", language: english, style: .natural)
        #expect(polished == "So I think we should ship it tomorrow.")
    }

    @Test func formalStyleExpandsContractions() {
        let polished = RuleBasedTextRefiner.polish("we can't ship it because it's not ready", language: english, style: .formal)
        #expect(polished == "We cannot ship it because it is not ready.")
    }

    @Test func casualStyleKeepsContractions() {
        let polished = RuleBasedTextRefiner.polish("we can't ship it", language: english, style: .casual)
        #expect(polished == "We can't ship it.")
    }

    @Test func capitalizesSentencesAndPronoun() {
        let polished = RuleBasedTextRefiner.polish("today i went home. then i slept", language: english, style: .natural)
        #expect(polished == "Today I went home. Then I slept.")
    }

    @Test func cleansChineseFillersAndPunctuation() {
        let polished = RuleBasedTextRefiner.polish("那个，我们明天 嗯 开会", language: mandarin, style: .natural)
        #expect(polished == "我们明天开会。")
    }

    @Test func cleansJapaneseFillers() {
        let polished = RuleBasedTextRefiner.polish("えーと、明日は あの 会議です", language: japanese, style: .natural)
        #expect(polished == "明日は会議です。")
    }

    @Test func refinerReportsEngineAndTitle() async throws {
        let refiner = RuleBasedTextRefiner()
        let result = try await refiner.refine(RefinementRequest(text: "hello there this is a test of the word spirit app", language: english, style: .concise, scenario: .notes))
        #expect(result.engine.modelID == "rule-based")
        #expect(result.title == "Hello there this is a test…")
        #expect(result.summary == "Hello there this is a test of the word spirit app")
    }
}

struct RefinementPipelineTests {
    struct FakeRefiner: TextRefiner {
        let descriptor: RefinerDescriptor
        let available: Bool
        let failWith: String?
        func isAvailable() async -> Bool { available }
        func refine(_ request: RefinementRequest) async throws -> RefinedText {
            if let failWith { throw RefinementError.allEnginesFailed(failWith) }
            return RefinedText(text: "[\(descriptor.displayName)] \(request.text)", title: descriptor.displayName, summary: "", engine: descriptor, latency: .zero)
        }
    }

    private let request = RefinementRequest(text: "raw words", language: .default, style: .natural, scenario: .notes)

    @Test func automaticPrefersOnDeviceWhenAvailable() async {
        let pipeline = RefinementPipeline(
            mode: .automatic,
            onDevice: FakeRefiner(descriptor: .init(displayName: "device", modelID: "d"), available: true, failWith: nil),
            cloud: FakeRefiner(descriptor: .init(displayName: "cloud", modelID: "c"), available: true, failWith: nil)
        )
        let (result, skipped) = await pipeline.refine(request)
        #expect(result.engine.displayName == "device")
        #expect(skipped.isEmpty)
    }

    @Test func automaticFallsThroughToCloudThenRules() async {
        let pipeline = RefinementPipeline(
            mode: .automatic,
            onDevice: FakeRefiner(descriptor: .init(displayName: "device", modelID: "d"), available: true, failWith: "boom"),
            cloud: FakeRefiner(descriptor: .init(displayName: "cloud", modelID: "c"), available: false, failWith: nil)
        )
        let (result, skipped) = await pipeline.refine(request)
        #expect(result.engine.modelID == "rule-based")
        #expect(skipped.count == 1)
        #expect(skipped.first?.contains("device") == true)
    }

    @Test func cloudModeSkipsOnDevice() async {
        let pipeline = RefinementPipeline(
            mode: .cloud,
            onDevice: FakeRefiner(descriptor: .init(displayName: "device", modelID: "d"), available: true, failWith: nil),
            cloud: FakeRefiner(descriptor: .init(displayName: "cloud", modelID: "c"), available: true, failWith: nil)
        )
        let (result, _) = await pipeline.refine(request)
        #expect(result.engine.displayName == "cloud")
    }

    @Test func promptCarriesLanguageStyleAndScenario() {
        let instructions = RefinementPrompt.instructions(for: RefinementRequest(text: "x", language: LanguageOption.option(for: "zh-HK")!, style: .business, scenario: .email))
        #expect(instructions.contains("Cantonese (Hong Kong)"))
        #expect(instructions.contains("professional business tone"))
        #expect(instructions.contains("email body"))
        #expect(instructions.contains("Never translate"))
    }
}

struct TranslationPipelineTests {
    struct FakeTranslator: Translator {
        let descriptor: TranslatorDescriptor
        let available: Bool
        let fail: Bool
        func isAvailable(from source: LanguageOption, to target: TargetLanguage) async -> Bool { available }
        func translate(_ text: String, from source: LanguageOption, to target: TargetLanguage) async throws -> TranslationOutput {
            if fail { throw TranslationFailure.failed("nope") }
            return TranslationOutput(target: target, text: "[\(descriptor.displayName)] \(text)", engine: descriptor, latency: .zero)
        }
    }

    @Test func automaticFallsBackToCloudWhenAppleFails() async throws {
        let pipeline = TranslationPipeline(
            mode: .automatic,
            apple: FakeTranslator(descriptor: .init(displayName: "apple", modelID: "a"), available: true, fail: true),
            cloud: FakeTranslator(descriptor: .init(displayName: "cloud", modelID: "c"), available: true, fail: false)
        )
        let output = try await pipeline.translate("hi", from: .default, to: TargetLanguage.target(for: "ja")!)
        #expect(output.engine.displayName == "cloud")
    }

    @Test func onDeviceModeThrowsWhenAppleUnavailable() async {
        let pipeline = TranslationPipeline(
            mode: .onDevice,
            apple: FakeTranslator(descriptor: .init(displayName: "apple", modelID: "a"), available: false, fail: false),
            cloud: FakeTranslator(descriptor: .init(displayName: "cloud", modelID: "c"), available: true, fail: false)
        )
        await #expect(throws: TranslationFailure.self) {
            _ = try await pipeline.translate("hi", from: .default, to: TargetLanguage.target(for: "ja")!)
        }
    }
}
