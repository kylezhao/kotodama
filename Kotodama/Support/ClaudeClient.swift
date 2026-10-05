//
//  ClaudeClient.swift
//  Kotodama
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation

/// Cloud models offered for polishing and translation.
enum CloudModel: String, CaseIterable, Identifiable, Sendable {
    case opus55 = "claude-opus-5-5"
    case sonnet55 = "claude-sonnet-5-5"
    case haiku45 = "claude-haiku-4-5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .opus55: "Claude Opus 5.5"
        case .sonnet55: "Claude Sonnet 5.5"
        case .haiku45: "Claude Haiku 4.5"
        }
    }

    /// Models that accept `output_config.effort` and the server-side `fallbacks` parameter.
    var supportsEffortAndFallbacks: Bool { self != .haiku45 }

    static let `default` = CloudModel.opus55
}

enum CloudError: LocalizedError, Equatable, Sendable {
    case missingAPIKey
    case unauthorized
    case rateLimited
    case overloaded
    case refused(String)
    case network(String)
    case decoding(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: String(localized: "Cloud features need an Anthropic API key. Add one in Settings.")
        case .unauthorized: String(localized: "The API key was rejected. Check it in Settings.")
        case .rateLimited: String(localized: "The cloud model is busy. Try again in a moment.")
        case .overloaded: String(localized: "Claude is overloaded right now. Try again shortly.")
        case .refused(let why): why.isEmpty ? String(localized: "The cloud model declined this request.") : why
        case .network(let detail): detail
        case .decoding(let detail): String(localized: "The cloud reply could not be read.") + " " + detail
        case .empty: String(localized: "The cloud model returned nothing.")
        }
    }
}

/// Thin client for the Anthropic Messages API with structured JSON output.
struct ClaudeClient: Sendable {
    struct Completion: Sendable {
        let json: Data
        let model: String
        let inputTokens: Int?
        let outputTokens: Int?
    }

    var apiKey: String
    var model: CloudModel
    var endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    var effort = "low"

    var isConfigured: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func complete(system: String, user: String, schema: [String: Any], maxTokens: Int = 2_048) async throws -> Completion {
        guard isConfigured else { throw CloudError.missingAPIKey }
        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": maxTokens,
            "system": [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]],
            "messages": [["role": "user", "content": user]],
        ]
        var outputConfig: [String: Any] = ["format": ["type": "json_schema", "schema": schema]]
        if model.supportsEffortAndFallbacks {
            outputConfig["effort"] = effort
            body["fallbacks"] = "default"
        }
        body["output_config"] = outputConfig

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if model.supportsEffortAndFallbacks {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError where urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost {
            throw CloudError.network(String(localized: "You're offline. On-device features keep working."))
        } catch {
            throw CloudError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw CloudError.network("No HTTP response.") }
        guard (200...299).contains(http.statusCode) else { throw Self.error(forStatus: http.statusCode, data: data) }

        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        if decoded.stopReason == "refusal" { throw CloudError.refused(decoded.stopDetails?.explanation ?? "") }
        let text = decoded.content.compactMap(\.text).joined()
        guard !text.isEmpty else { throw CloudError.empty }
        return Completion(
            json: Data(text.utf8),
            model: decoded.model ?? model.rawValue,
            inputTokens: decoded.usage?.inputTokens,
            outputTokens: decoded.usage?.outputTokens
        )
    }

    struct MessagesResponse: Decodable {
        struct ContentBlock: Decodable { let type: String; let text: String? }
        struct Usage: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
            enum CodingKeys: String, CodingKey { case inputTokens = "input_tokens"; case outputTokens = "output_tokens" }
        }
        struct StopDetails: Decodable { let category: String?; let explanation: String? }
        let model: String?
        let stopReason: String?
        let stopDetails: StopDetails?
        let content: [ContentBlock]
        let usage: Usage?
        enum CodingKeys: String, CodingKey {
            case model, content, usage
            case stopReason = "stop_reason"
            case stopDetails = "stop_details"
        }
    }

    struct APIErrorEnvelope: Decodable {
        struct APIError: Decodable { let type: String?; let message: String? }
        let error: APIError?
    }

    static func error(forStatus status: Int, data: Data) -> CloudError {
        let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.error?.message
        switch status {
        case 401, 403: return .unauthorized
        case 429: return .rateLimited
        case 529: return .overloaded
        default: return .network(message ?? "HTTP \(status)")
        }
    }
}
