//
//  OnDeviceTextRefiner.swift
//  Kotodama
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import FoundationModels

/// Polishes text with Apple's on-device language model using guided generation.
final class OnDeviceTextRefiner: TextRefiner {
    let descriptor = RefinerDescriptor(displayName: "Apple Intelligence", modelID: "SystemLanguageModel (on-device)")

    @Generable(description: "A polished version of a spoken transcript.")
    struct Output {
        @Guide(description: "The polished text, in the same language as the input.")
        var text: String
        @Guide(description: "A title of at most six words.")
        var title: String
        @Guide(description: "A one-sentence summary.")
        var summary: String
    }

    private let model: SystemLanguageModel

    init(model: SystemLanguageModel = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)) {
        self.model = model
    }

    func isAvailable() async -> Bool { model.isAvailable }

    func refine(_ request: RefinementRequest) async throws -> RefinedText {
        guard model.isAvailable else { throw RefinementError.unavailable }
        let clock = ContinuousClock()
        let start = clock.now
        let instructions = RefinementPrompt.instructions(for: request)
        let session = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(
            to: RefinementPrompt.userMessage(for: request),
            generating: Output.self,
            options: GenerationOptions(temperature: 0.3, maximumResponseTokens: 900)
        )
        let inputTokens = try? await model.tokenCount(for: request.text)
        let outputTokens = try? await model.tokenCount(for: response.content.text)
        return RefinedText(
            text: response.content.text.trimmingCharacters(in: .whitespacesAndNewlines),
            title: response.content.title,
            summary: response.content.summary,
            engine: descriptor,
            latency: clock.now - start,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }
}

enum RefinementError: LocalizedError, Equatable {
    case unavailable
    case allEnginesFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "The on-device model is not available.")
        case .allEnginesFailed(let detail): String(localized: "Polishing failed.") + " " + detail
        }
    }
}
