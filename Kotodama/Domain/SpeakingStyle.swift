//
//  SpeakingStyle.swift
//  Kotodama
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation

/// How the polished text should sound.
enum SpeakingStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case natural, formal, casual, concise, business, academic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural: String(localized: "Natural")
        case .formal: String(localized: "Formal")
        case .casual: String(localized: "Casual")
        case .concise: String(localized: "Concise")
        case .business: String(localized: "Business")
        case .academic: String(localized: "Academic")
        }
    }

    var symbol: String {
        switch self {
        case .natural: "leaf.fill"
        case .formal: "crown.fill"
        case .casual: "face.smiling.fill"
        case .concise: "scissors"
        case .business: "briefcase.fill"
        case .academic: "graduationcap.fill"
        }
    }

    /// Guidance handed to the refining model.
    var instruction: String {
        switch self {
        case .natural: "Keep the speaker's natural voice. Fix grammar and punctuation, remove filler words and false starts, and keep the meaning and length."
        case .formal: "Rewrite in a polite, formal register with complete sentences and no slang."
        case .casual: "Rewrite in a relaxed, friendly register, as if messaging a friend, while staying clear."
        case .concise: "Rewrite as briefly as possible without losing any fact, decision or request. Prefer short sentences."
        case .business: "Rewrite in a professional business tone suitable for colleagues and clients. Be clear, courteous and action-oriented."
        case .academic: "Rewrite in a precise, neutral academic register with well-structured sentences and no colloquialisms."
        }
    }
}

/// Where the text will be used. Shapes structure and formatting.
enum UsageScenario: String, Codable, CaseIterable, Identifiable, Sendable {
    case notes, message, email, meeting, lecture, travel, social

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: String(localized: "Notes")
        case .message: String(localized: "Message")
        case .email: String(localized: "Email")
        case .meeting: String(localized: "Meeting")
        case .lecture: String(localized: "Lecture")
        case .travel: String(localized: "Travel")
        case .social: String(localized: "Social post")
        }
    }

    var symbol: String {
        switch self {
        case .notes: "note.text"
        case .message: "bubble.left.fill"
        case .email: "envelope.fill"
        case .meeting: "person.3.fill"
        case .lecture: "book.fill"
        case .travel: "airplane"
        case .social: "megaphone.fill"
        }
    }

    var instruction: String {
        switch self {
        case .notes: "Format as personal notes: short paragraphs, keep every detail the speaker mentioned."
        case .message: "Format as a chat message: one or two short paragraphs, no greeting or sign-off unless spoken."
        case .email: "Format as an email body: a brief greeting if appropriate, clear paragraphs, and a courteous closing line."
        case .meeting: "Format as meeting notes: group related points, call out decisions and action items on their own lines."
        case .lecture: "Format as lecture notes: organise into key points with the terminology preserved exactly."
        case .travel: "Format for a traveller: keep names, places, numbers, times and prices exact and easy to scan."
        case .social: "Format as a social media post: punchy, one to three sentences, keep hashtags if spoken."
        }
    }
}
