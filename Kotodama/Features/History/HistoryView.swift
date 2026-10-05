//
//  HistoryView.swift
//  Kotodama
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transcript.createdAt, order: .reverse) private var transcripts: [Transcript]

    var body: some View {
        NavigationStack {
            ZStack {
                SpiritFieldBackground()
                if transcripts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "scroll.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(KotodamaTheme.titleGradient)
                        Text("No words recorded yet")
                            .font(KotodamaTheme.heading(.title3))
                            .foregroundStyle(KotodamaTheme.titleGradient)
                        Text("Everything you speak is kept here with its refined text and translations.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(transcripts) { transcript in
                                NavigationLink(value: transcript) {
                                    TranscriptRow(transcript: transcript)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        modelContext.delete(transcript)
                                        try? modelContext.save()
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: Transcript.self) { TranscriptDetailView(transcript: $0) }
        }
    }
}

private struct TranscriptRow: View {
    let transcript: Transcript

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(transcript.language.flag)
                .font(.title2)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.tint(KotodamaTheme.spirit.opacity(0.15)), in: .circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(transcript.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(transcript.polishedText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Badge(text: transcript.recognitionMode.title, systemImage: transcript.recognitionMode.symbol, tint: KotodamaTheme.spirit)
                    if !transcript.translations.isEmpty {
                        Badge(text: "\(transcript.translations.count)", systemImage: "globe", tint: KotodamaTheme.paper)
                    }
                    Spacer()
                    Text(transcript.createdAt, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .talisman(cornerRadius: 18)
    }
}

struct TranscriptDetailView: View {
    @Environment(AppSettings.self) private var settings
    let transcript: Transcript

    var body: some View {
        ZStack {
            SpiritFieldBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("Spoken words", systemImage: "waveform") {
                        Text(transcript.rawText).font(KotodamaTheme.transcript(18)).textSelection(.enabled)
                    }
                    section("Refined", systemImage: "sparkles") {
                        Text(transcript.polishedText).font(KotodamaTheme.transcript(18)).textSelection(.enabled)
                        if let summary = transcript.summary, !summary.isEmpty {
                            Text(summary).font(.footnote).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            Badge(text: transcript.style.title, systemImage: transcript.style.symbol)
                            Badge(text: transcript.scenario.title, systemImage: transcript.scenario.symbol)
                            if let refiner = transcript.refinerName {
                                Badge(text: refiner, systemImage: "wand.and.stars", tint: KotodamaTheme.blossom)
                            }
                        }
                    }
                    if !transcript.translations.isEmpty {
                        section("Carried across", systemImage: "globe.asia.australia.fill") {
                            ForEach(transcript.sortedTranslations) { translation in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("\(translation.target?.flag ?? "") \(translation.target?.nativeName ?? translation.targetLanguageID)")
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Badge(text: translation.translatorName, systemImage: "arrow.left.arrow.right", tint: KotodamaTheme.spirit)
                                    }
                                    Text(translation.text).font(KotodamaTheme.transcript(17)).textSelection(.enabled)
                                }
                            }
                        }
                    }
                    if settings.showMetrics {
                        section("Metrics", systemImage: "gauge.with.dots.needle.33percent") {
                            metricRow("Recognizer", "\(transcript.recognizerName) · \(transcript.recognizerModelID)")
                            metricRow("Audio", String(format: "%.1f s", transcript.audioDuration))
                            metricRow("Recognition", String(format: "%.2f s", transcript.recognitionSeconds))
                            if let first = transcript.firstResultSeconds { metricRow("First result", String(format: "%.2f s", first)) }
                            if let refiner = transcript.refinerModelID { metricRow("Refiner", refiner) }
                            if let seconds = transcript.refinementSeconds { metricRow("Refinement", String(format: "%.2f s", seconds)) }
                            ForEach(transcript.sortedTranslations) { translation in
                                metricRow("→ \(translation.targetLanguageID)", "\(translation.translatorModelID) · " + String(format: "%.2f s", translation.seconds))
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle(transcript.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: TranscriptExporter.markdown(for: transcript), preview: SharePreview(transcript.title)) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(KotodamaTheme.heading(.headline))
                .foregroundStyle(KotodamaTheme.titleGradient)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .talisman()
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit()).multilineTextAlignment(.trailing)
        }
    }
}

/// Markdown export so recordings can be shared and kept as test cases.
enum TranscriptExporter {
    static func markdown(for transcript: Transcript) -> String {
        var lines: [String] = []
        lines.append("# \(transcript.title)")
        lines.append("")
        lines.append("- Language: \(transcript.language.name) (\(transcript.languageID))")
        lines.append("- Recognizer: \(transcript.recognizerName) · \(transcript.recognizerModelID) · \(transcript.recognitionMode.title)")
        lines.append("- Audio: \(String(format: "%.1f", transcript.audioDuration)) s, recognition \(String(format: "%.2f", transcript.recognitionSeconds)) s")
        if let refiner = transcript.refinerModelID, let seconds = transcript.refinementSeconds {
            lines.append("- Refiner: \(refiner) · \(String(format: "%.2f", seconds)) s · \(transcript.style.title) / \(transcript.scenario.title)")
        }
        lines.append("- Recorded: \(transcript.createdAt.formatted(date: .abbreviated, time: .shortened))")
        lines.append("")
        lines.append("## Spoken words")
        lines.append("")
        lines.append(transcript.rawText)
        lines.append("")
        lines.append("## Refined")
        lines.append("")
        lines.append(transcript.polishedText)
        if let summary = transcript.summary, !summary.isEmpty {
            lines.append("")
            lines.append("_\(summary)_")
        }
        if !transcript.translations.isEmpty {
            lines.append("")
            lines.append("## Translations")
            for translation in transcript.sortedTranslations {
                lines.append("")
                lines.append("### \(translation.target?.name ?? translation.targetLanguageID) (\(translation.translatorModelID), \(String(format: "%.2f", translation.seconds)) s)")
                lines.append("")
                lines.append(translation.text)
            }
        }
        return lines.joined(separator: "\n")
    }
}
