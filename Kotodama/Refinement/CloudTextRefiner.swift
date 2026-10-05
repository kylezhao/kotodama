//
//  CloudTextRefiner.swift
//  Kotodama
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation

/// Polishes text with Claude through the Messages API, using structured output.
struct CloudTextRefiner: TextRefiner {
    let client: ClaudeClient

    var descriptor: RefinerDescriptor { RefinerDescriptor(displayName: "Claude", modelID: client.model.rawValue) }

    func isAvailable() async -> Bool { client.isConfigured }

    func refine(_ request: RefinementRequest) async throws -> RefinedText {
        let clock = ContinuousClock()
        let start = clock.now
        let completion = try await client.complete(
            system: RefinementPrompt.instructions(for: request),
            user: RefinementPrompt.userMessage(for: request),
            schema: RefinementPrompt.schema,
            maxTokens: 2_048
        )
        let payload: PolishedPayload
        do {
            payload = try JSONDecoder().decode(PolishedPayload.self, from: completion.json)
        } catch {
            throw CloudError.decoding(error.localizedDescription)
        }
        return RefinedText(
            text: payload.text.trimmingCharacters(in: .whitespacesAndNewlines),
            title: payload.title,
            summary: payload.summary,
            engine: RefinerDescriptor(displayName: "Claude", modelID: completion.model),
            latency: clock.now - start,
            inputTokens: completion.inputTokens,
            outputTokens: completion.outputTokens
        )
    }
}

/// Chooses a refiner according to the intelligence mode and falls back down the chain.
struct RefinementPipeline: Sendable {
    var mode: IntelligenceMode
    var onDevice: any TextRefiner
    var cloud: any TextRefiner
    var rules: any TextRefiner = RuleBasedTextRefiner()

    func orderedRefiners() async -> [any TextRefiner] {
        switch mode {
        case .onDevice: return [onDevice, rules]
        case .cloud: return [cloud, rules]
        case .automatic:
            var chain: [any TextRefiner] = []
            if await onDevice.isAvailable() { chain.append(onDevice) }
            if await cloud.isAvailable() { chain.append(cloud) }
            chain.append(rules)
            return chain
        }
    }

    /// Tries each refiner in order and returns the first success, with the errors of the ones that failed.
    func refine(_ request: RefinementRequest) async -> (RefinedText, skipped: [String]) {
        var skipped: [String] = []
        for refiner in await orderedRefiners() {
            do {
                return (try await refiner.refine(request), skipped)
            } catch {
                skipped.append("\(refiner.descriptor.displayName): \(error.localizedDescription)")
            }
        }
        // The rule-based refiner never throws, so this is unreachable in practice.
        let fallback = RefinedText(text: request.text, title: Transcript.makeTitle(from: request.text), summary: "", engine: rules.descriptor, latency: .zero)
        return (fallback, skipped)
    }
}
