//
//  RuleBasedTextRefiner.swift
//  Kotodama
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation

/// Deterministic clean-up used when no language model is available. Removes fillers and
/// repeated words, fixes capitalisation and terminal punctuation, and applies light style rules.
struct RuleBasedTextRefiner: TextRefiner {
    let descriptor = RefinerDescriptor(displayName: "Kotodama Rules", modelID: "rule-based")

    func isAvailable() async -> Bool { true }

    func refine(_ request: RefinementRequest) async throws -> RefinedText {
        let clock = ContinuousClock()
        let start = clock.now
        let text = Self.polish(request.text, language: request.language, style: request.style)
        return RefinedText(
            text: text,
            title: Transcript.makeTitle(from: text),
            summary: Self.firstSentence(of: text),
            engine: descriptor,
            latency: clock.now - start
        )
    }

    // MARK: - Rules

    static let latinFillers = ["um", "uh", "uhm", "erm", "hmm", "you know", "i mean", "sort of", "kind of"]
    static let chineseFillers = ["那个", "这个那个", "嗯", "呃", "啊", "就是说", "然后呢"]
    static let japaneseFillers = ["えーと", "えっと", "えー", "あのー", "あの", "そのー", "まあ", "なんか"]

    static let contractions: [(String, String)] = [
        ("don't", "do not"), ("doesn't", "does not"), ("didn't", "did not"), ("can't", "cannot"),
        ("won't", "will not"), ("isn't", "is not"), ("aren't", "are not"), ("wasn't", "was not"),
        ("weren't", "were not"), ("i'm", "I am"), ("it's", "it is"), ("that's", "that is"),
        ("we're", "we are"), ("you're", "you are"), ("they're", "they are"), ("let's", "let us"),
        ("i've", "I have"), ("we've", "we have"), ("i'll", "I will"), ("we'll", "we will"),
        ("gonna", "going to"), ("wanna", "want to"), ("gotta", "have to"),
    ]

    static func polish(_ raw: String, language: LanguageOption, style: SpeakingStyle) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }
        let isCJK = language.group == .chinese || language.group == .japanese || language.id.hasPrefix("ko")

        if isCJK {
            for filler in chineseFillers + japaneseFillers {
                text = text.replacingOccurrences(of: filler + "，", with: "")
                text = text.replacingOccurrences(of: filler + "、", with: "")
                text = text.replacingOccurrences(of: filler, with: "")
            }
            text = text.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"[，、。]{2,}"#, with: "。", options: .regularExpression)
            if let last = text.last, !"。！？…」』".contains(last) {
                text.append(language.group == .japanese ? "。" : "。")
            }
            return text
        }

        for filler in latinFillers {
            // Swallow the filler together with any comma that framed it: "should, uh, ship" -> "should ship".
            let pattern = #"(?i)(?:,\s*)?\b"# + NSRegularExpression.escapedPattern(for: filler) + #"\b(?:\s*,)?"#
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        // Repeated words: "the the" -> "the".
        text = text.replacingOccurrences(of: #"(?i)\b(\w+)(\s+\1\b)+"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if style == .formal || style == .business || style == .academic {
            for (short, long) in contractions {
                text = text.replacingOccurrences(of: #"(?i)\b"# + NSRegularExpression.escapedPattern(for: short) + #"\b"#, with: long, options: .regularExpression)
            }
        }

        text = capitalizeSentences(text)
        if let last = text.last, !".!?…\"'”’".contains(last) {
            text.append(".")
        }
        return text
    }

    static func capitalizeSentences(_ text: String) -> String {
        var result = ""
        var capitalizeNext = true
        for character in text {
            if capitalizeNext, character.isLetter {
                result.append(contentsOf: String(character).uppercased())
                capitalizeNext = false
            } else {
                result.append(character)
            }
            if ".!?".contains(character) { capitalizeNext = true }
        }
        // Standalone pronoun "i".
        return result.replacingOccurrences(of: #"\bi\b"#, with: "I", options: .regularExpression)
    }

    static func firstSentence(of text: String) -> String {
        let separators = CharacterSet(charactersIn: ".!?。！？")
        let first = text.components(separatedBy: separators).first?.trimmingCharacters(in: .whitespaces) ?? text
        return first.isEmpty ? text : first
    }
}
