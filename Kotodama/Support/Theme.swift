//
//  Theme.swift
//  Kotodama
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import SwiftUI

/// Ink-and-spirit palette: a night shrine with glowing word spirits.
enum KotodamaTheme {
    static let inkTop = Color(red: 0.04, green: 0.06, blue: 0.16)
    static let inkMiddle = Color(red: 0.07, green: 0.20, blue: 0.30)
    static let inkBottom = Color(red: 0.03, green: 0.09, blue: 0.14)
    static let spirit = Color(red: 0.56, green: 0.90, blue: 0.96)
    static let paper = Color(red: 0.96, green: 0.86, blue: 0.64)
    static let vermilion = Color(red: 0.93, green: 0.36, blue: 0.33)
    static let blossom = Color(red: 0.95, green: 0.58, blue: 0.78)

    static let titleGradient = LinearGradient(colors: [paper, .white, spirit], startPoint: .leading, endPoint: .trailing)
    static let orbGradient = LinearGradient(colors: [spirit, Color(red: 0.35, green: 0.55, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let recordingGradient = LinearGradient(colors: [vermilion, blossom], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func heading(_ style: Font.TextStyle = .title2) -> Font {
        .system(style, design: .rounded, weight: .bold)
    }

    static func transcript(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }
}

/// Night sky with drifting word spirits. `energy` (0...1) makes them glow and rise faster.
struct SpiritFieldBackground: View {
    var energy: Float = 0

    private static let glyphs = ["言", "霊", "音", "声", "心", "光", "風", "詞", "語", "魂"]

    private struct Spirit {
        let x: CGFloat
        let baseY: CGFloat
        let size: CGFloat
        let speed: Double
        let glyph: String
        let phase: Double
    }

    private static let spirits: [Spirit] = {
        var generator = SeededGenerator(seed: 20261005)
        return (0..<18).map { index in
            Spirit(
                x: CGFloat.random(in: 0.05...0.95, using: &generator),
                baseY: CGFloat.random(in: 0.1...1.0, using: &generator),
                size: CGFloat.random(in: 14...30, using: &generator),
                speed: Double.random(in: 0.015...0.04, using: &generator),
                glyph: glyphs[index % glyphs.count],
                phase: Double.random(in: 0...(2 * .pi), using: &generator)
            )
        }
    }()

    var body: some View {
        ZStack {
            LinearGradient(colors: [KotodamaTheme.inkTop, KotodamaTheme.inkMiddle, KotodamaTheme.inkBottom], startPoint: .top, endPoint: .bottom)
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                Canvas { canvas, size in
                    let glow = 0.35 + Double(energy) * 0.65
                    for spirit in Self.spirits {
                        let rise = (time * spirit.speed * (1 + Double(energy) * 2) + Double(spirit.baseY)).truncatingRemainder(dividingBy: 1.2)
                        let y = size.height * (1.1 - rise)
                        let sway = sin(time * 0.6 + spirit.phase) * 12
                        let point = CGPoint(x: size.width * spirit.x + sway, y: y)
                        let pulse = 0.5 + 0.5 * sin(time * 1.3 + spirit.phase)
                        let opacity = (0.18 + 0.32 * pulse) * glow
                        var text = Text(spirit.glyph)
                            .font(.system(size: spirit.size, weight: .light, design: .serif))
                        text = text.foregroundColor(KotodamaTheme.spirit.opacity(opacity))
                        canvas.draw(text, at: point)
                    }
                }
            }
            RadialGradient(colors: [KotodamaTheme.spirit.opacity(0.10 + Double(energy) * 0.25), .clear], center: .center, startRadius: 20, endRadius: 320)
                .animation(.easeOut(duration: 0.2), value: energy)
        }
        .ignoresSafeArea()
    }
}

/// Deterministic generator so the spirit field is identical on every launch.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Glass card with a thin paper-gold rim, the app's "talisman" frame.
struct TalismanStyle: ViewModifier {
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [KotodamaTheme.paper.opacity(0.7), KotodamaTheme.paper.opacity(0.1), KotodamaTheme.spirit.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            }
    }
}

extension View {
    func talisman(cornerRadius: CGFloat = 22) -> some View {
        modifier(TalismanStyle(cornerRadius: cornerRadius))
    }
}

/// Small capsule badge used for engines and metrics.
struct Badge: View {
    var text: String
    var systemImage: String
    var tint: Color = KotodamaTheme.paper

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(tint)
            .glassEffect(.regular.tint(tint.opacity(0.18)), in: .capsule)
    }
}

/// Selectable chip used for styles, scenarios and languages.
struct Chip: View {
    var title: String
    var systemImage: String? = nil
    var emoji: String? = nil
    var isSelected: Bool
    var tint: Color = KotodamaTheme.paper
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let emoji { Text(emoji) }
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.footnote.weight(isSelected ? .semibold : .regular))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? tint : .primary)
        .glassEffect(.regular.tint(isSelected ? tint.opacity(0.28) : .clear).interactive(), in: .capsule)
    }
}
