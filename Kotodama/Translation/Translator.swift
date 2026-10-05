//
//  Translator.swift
//  Kotodama
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import Observation
import Translation

struct TranslatorDescriptor: Hashable, Sendable {
    let displayName: String
    let modelID: String
}

struct TranslationOutput: Equatable, Sendable {
    var target: TargetLanguage
    var text: String
    var engine: TranslatorDescriptor
    var latency: Duration
}

protocol Translator: Sendable {
    var descriptor: TranslatorDescriptor { get }
    func isAvailable(from source: LanguageOption, to target: TargetLanguage) async -> Bool
    func translate(_ text: String, from source: LanguageOption, to target: TargetLanguage) async throws -> TranslationOutput
}

enum TranslationFailure: LocalizedError, Equatable {
    case unsupportedPair(String, String)
    case needsDownload(String)
    case unavailable
    case noEngine(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedPair(let from, let to): String(localized: "Apple Translate cannot translate \(from) to \(to).")
        case .needsDownload(let language): String(localized: "The \(language) translation model needs to be downloaded first.")
        case .unavailable: String(localized: "Translation is not available right now.")
        case .noEngine(let detail): detail
        case .failed(let detail): detail
        }
    }
}

/// Bridges Apple's Translation framework, whose sessions are only handed out through the
/// `translationTask` view modifier, to an async translate call. One request runs at a time.
@MainActor
@Observable
final class AppleTranslationCoordinator {
    private struct Pending {
        let text: String
        let continuation: CheckedContinuation<String, any Error>
    }

    /// Bound to `.translationTask` on the hosting view. Changing it requests a new session.
    private(set) var configuration: TranslationSession.Configuration?
    private var pending: Pending?
    private var isBusy = false

    func translate(_ text: String, from source: Locale.Language, to target: Locale.Language) async throws -> String {
        while isBusy {
            try await Task.sleep(for: .milliseconds(20))
        }
        isBusy = true
        defer { isBusy = false }
        return try await withCheckedThrowingContinuation { continuation in
            pending = Pending(text: text, continuation: continuation)
            var next = TranslationSession.Configuration(source: source, target: target)
            if var existing = configuration, existing.source == source, existing.target == target {
                existing.invalidate()
                next = existing
            }
            configuration = next
        }
    }

    /// Called by the view modifier whenever a session is available for the current configuration.
    func handle(_ session: TranslationSession) async {
        guard let pending else { return }
        self.pending = nil
        do {
            try await session.prepareTranslation()
            let response = try await session.translate(pending.text)
            pending.continuation.resume(returning: response.targetText)
        } catch {
            pending.continuation.resume(throwing: TranslationFailure.failed(error.localizedDescription))
        }
    }
}

/// On-device translation through Apple's Translation framework.
struct AppleTranslator: Translator {
    let coordinator: AppleTranslationCoordinator
    let descriptor = TranslatorDescriptor(displayName: "Apple Translate", modelID: "Translation framework (on-device)")

    func isAvailable(from source: LanguageOption, to target: TargetLanguage) async -> Bool {
        let status = await LanguageAvailability().status(from: source.language, to: target.language)
        return status != .unsupported
    }

    func translate(_ text: String, from source: LanguageOption, to target: TargetLanguage) async throws -> TranslationOutput {
        let clock = ContinuousClock()
        let start = clock.now
        let status = await LanguageAvailability().status(from: source.language, to: target.language)
        guard status != .unsupported else { throw TranslationFailure.unsupportedPair(source.name, target.name) }
        let translated = try await coordinator.translate(text, from: source.language, to: target.language)
        return TranslationOutput(target: target, text: translated, engine: descriptor, latency: clock.now - start)
    }
}

/// Translation through Claude, used when Apple Translate lacks the pair or the user prefers the cloud.
struct CloudTranslator: Translator {
    let client: ClaudeClient

    var descriptor: TranslatorDescriptor { TranslatorDescriptor(displayName: "Claude", modelID: client.model.rawValue) }

    func isAvailable(from source: LanguageOption, to target: TargetLanguage) async -> Bool { client.isConfigured }

    func translate(_ text: String, from source: LanguageOption, to target: TargetLanguage) async throws -> TranslationOutput {
        let clock = ContinuousClock()
        let start = clock.now
        let system = """
        You are Kotodama, a careful translator. Translate the user's text from \(source.name) into \(target.name) \
        (\(target.nativeName)). Preserve meaning, tone, names and numbers. Return only the translation.
        """
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["translation"],
            "properties": ["translation": ["type": "string", "description": "The translated text."]],
        ]
        let completion = try await client.complete(system: system, user: text, schema: schema, maxTokens: 2_048)
        struct Payload: Decodable { let translation: String }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: completion.json)
        } catch {
            throw CloudError.decoding(error.localizedDescription)
        }
        return TranslationOutput(
            target: target,
            text: payload.translation.trimmingCharacters(in: .whitespacesAndNewlines),
            engine: TranslatorDescriptor(displayName: "Claude", modelID: completion.model),
            latency: clock.now - start
        )
    }
}

/// Picks a translator per language pair according to the intelligence mode.
struct TranslationPipeline: Sendable {
    var mode: IntelligenceMode
    var apple: any Translator
    var cloud: any Translator

    func translate(_ text: String, from source: LanguageOption, to target: TargetLanguage) async throws -> TranslationOutput {
        let order: [any Translator]
        switch mode {
        case .onDevice: order = [apple]
        case .cloud: order = [cloud]
        case .automatic: order = [apple, cloud]
        }
        var lastError: (any Error)?
        var skipped: [String] = []
        for translator in order {
            guard await translator.isAvailable(from: source, to: target) else {
                skipped.append(translator.descriptor.displayName)
                continue
            }
            do {
                return try await translator.translate(text, from: source, to: target)
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        #if targetEnvironment(simulator)
        let hint = String(localized: "Apple Translate does not run in the Simulator. Add an Anthropic API key in Settings for cloud translation, or run on a device.")
        #else
        let hint = String(localized: "Apple Translate cannot handle \(source.name) → \(target.name). Add an Anthropic API key in Settings for cloud translation.")
        #endif
        throw TranslationFailure.noEngine(skipped.isEmpty ? TranslationFailure.unavailable.localizedDescription : hint)
    }
}
