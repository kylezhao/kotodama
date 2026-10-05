//
//  SpeakView.swift
//  Kotodama
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SpeakView: View {
    @State private var viewModel: SpeakViewModel
    @Environment(AppSettings.self) private var settings
    @State private var showingImporter = false

    init(settings: AppSettings, modelContext: ModelContext, translationCoordinator: AppleTranslationCoordinator) {
        _viewModel = State(initialValue: SpeakViewModel(settings: settings, modelContext: modelContext, translationCoordinator: translationCoordinator))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SpiritFieldBackground(energy: viewModel.isListening ? viewModel.capture.level : 0)
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        headerCard
                        transcriptCard
                        if let refined = viewModel.refined {
                            refinedCard(refined)
                                .id("refined")
                        }
                        if !viewModel.translations.isEmpty || !viewModel.translationErrors.isEmpty {
                            translationsCard
                        }
                        if settings.showMetrics, let metrics = viewModel.recognitionMetrics {
                            metricsCard(metrics)
                        }
                        if let error = viewModel.errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(KotodamaTheme.vermilion)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .talisman(cornerRadius: 16)
                                .accessibilityIdentifier("errorLabel")
                        }
                    }
                    .padding()
                    .padding(.bottom, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.refined) { _, refined in
                    guard refined != nil else { return }
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        proxy.scrollTo("refined", anchor: .top)
                    }
                }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { controls }
            .navigationTitle("Kotodama")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("Try a sample") {
                            ForEach(SpeakViewModel.sampleLanguages) { language in
                                Button {
                                    viewModel.transcribeSample(language)
                                } label: {
                                    Label("\(language.flag) \(language.name)", systemImage: "waveform")
                                }
                                .accessibilityIdentifier("sample-\(language.id)")
                            }
                        }
                        Button {
                            showingImporter = true
                        } label: {
                            Label("Import audio file", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "waveform.badge.plus")
                    }
                    .accessibilityIdentifier("sampleMenu")
                    .disabled(viewModel.isBusy)
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.audio, .wav, .mpeg4Audio, .mp3]) { result in
                if case .success(let url) = result {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    let copy = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                    try? FileManager.default.removeItem(at: copy)
                    try? FileManager.default.copyItem(at: url, to: copy)
                    viewModel.transcribe(fileURL: copy)
                }
            }
            .task(id: "\(settings.sourceLanguageID)-\(settings.recognitionMode.rawValue)") {
                await viewModel.refreshAvailability()
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(LanguageOption.Group.allCases, id: \.self) { group in
                        Section(group.title) {
                            ForEach(LanguageOption.recognitionCandidates.filter { $0.group == group }) { option in
                                Button {
                                    settings.sourceLanguageID = option.id
                                } label: {
                                    Label {
                                        Text(option.name)
                                        Text(option.nativeName)
                                    } icon: {
                                        Text(option.flag)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(viewModel.language.flag)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(viewModel.language.nativeName).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(viewModel.language.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
                        }
                        Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .accessibilityIdentifier("languageMenu")
                .disabled(viewModel.isBusy)

                Spacer()

                Picker("Engine", selection: $settings.recognitionMode) {
                    ForEach(RecognitionMode.allCases) { mode in
                        Image(systemName: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
                .accessibilityIdentifier("modePicker")
                .disabled(viewModel.isBusy)
            }
            HStack(spacing: 8) {
                availabilityBadge
                if let descriptor = viewModel.activeDescriptor {
                    Text(descriptor.modelID)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
        .padding(14)
        .talisman()
    }

    @ViewBuilder
    private var availabilityBadge: some View {
        switch viewModel.availability {
        case .ready:
            Badge(text: settings.recognitionMode.title, systemImage: settings.recognitionMode.symbol, tint: KotodamaTheme.spirit)
        case .needsDownload:
            Button {
                Task { await viewModel.downloadModel() }
            } label: {
                Badge(text: String(localized: "Download model"), systemImage: "arrow.down.circle.fill", tint: KotodamaTheme.paper)
            }
            .buttonStyle(.plain)
        case .unavailable(let reason):
            Badge(text: reason, systemImage: "exclamationmark.triangle.fill", tint: KotodamaTheme.vermilion)
        }
    }

    // MARK: - Cards

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Spoken words", systemImage: "waveform")
                    .font(KotodamaTheme.heading(.headline))
                    .foregroundStyle(KotodamaTheme.titleGradient)
                Spacer()
                if viewModel.isListening {
                    HStack(spacing: 5) {
                        Circle().fill(KotodamaTheme.vermilion).frame(width: 7, height: 7)
                        Text("LIVE").font(.caption2.weight(.bold)).foregroundStyle(KotodamaTheme.vermilion)
                    }
                }
            }
            if viewModel.liveText.isEmpty {
                Text(viewModel.statusLine)
                    .font(KotodamaTheme.transcript(18))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    (Text(viewModel.finalizedText) + Text(viewModel.volatileText.isEmpty ? "" : (viewModel.finalizedText.isEmpty ? "" : " ") + viewModel.volatileText).foregroundColor(.secondary))
                        .font(KotodamaTheme.transcript())
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("transcriptText")
                        .animation(.easeOut(duration: 0.15), value: viewModel.liveText)
                    if !viewModel.isBusy, !viewModel.finalizedText.isEmpty {
                        SpeakButton(text: viewModel.finalizedText, id: "spoken", voiceLanguage: viewModel.language.voiceLanguage)
                    }
                }
            }
            if case .preparing(let progress) = viewModel.phase {
                ProgressView(value: progress).tint(KotodamaTheme.spirit)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .talisman()
    }

    private func refinedCard(_ refined: RefinedText) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label("Refined", systemImage: "sparkles")
                    .font(KotodamaTheme.heading(.headline))
                    .foregroundStyle(KotodamaTheme.titleGradient)
                Spacer()
                Badge(text: refined.engine.displayName, systemImage: "wand.and.stars", tint: KotodamaTheme.blossom)
            }
            Text(refined.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KotodamaTheme.paper)
            HStack(alignment: .top, spacing: 10) {
                Text(refined.text)
                    .font(KotodamaTheme.transcript())
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("polishedText")
                if !viewModel.isBusy {
                    SpeakButton(text: refined.text, id: "refined", voiceLanguage: viewModel.language.voiceLanguage, tint: KotodamaTheme.blossom)
                }
            }
            HStack(spacing: 8) {
                Badge(text: settings.style.title, systemImage: settings.style.symbol)
                Badge(text: settings.scenario.title, systemImage: settings.scenario.symbol)
                Spacer()
                if settings.showMetrics {
                    Text(String(format: "%.2fs", refined.latency.seconds))
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if !viewModel.skippedRefiners.isEmpty, settings.showMetrics {
                Text(viewModel.skippedRefiners.joined(separator: "\n"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .talisman()
    }

    private var translationsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Carried across", systemImage: "globe.asia.australia.fill")
                .font(KotodamaTheme.heading(.headline))
                .foregroundStyle(KotodamaTheme.titleGradient)
            ForEach(viewModel.translations, id: \.target.id) { translation in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("\(translation.target.flag) \(translation.target.nativeName)")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Badge(text: translation.engine.displayName, systemImage: "arrow.left.arrow.right", tint: KotodamaTheme.spirit)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        Text(translation.text)
                            .font(KotodamaTheme.transcript(18))
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        if !viewModel.isBusy {
                            SpeakButton(text: translation.text, id: "translation-\(translation.target.id)", voiceLanguage: translation.target.voiceLanguage)
                        }
                    }
                    .padding(.bottom, 2)
                }
                .accessibilityIdentifier("translation-\(translation.target.id)")
            }
            ForEach(viewModel.translationErrors, id: \.self) { error in
                Text(error).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .talisman()
    }

    private func metricsCard(_ metrics: RecognitionMetrics) -> some View {
        HStack(spacing: 14) {
            metric("Audio", String(format: "%.1fs", metrics.audioSeconds))
            metric("Recognition", String(format: "%.1fs", metrics.wallClockSeconds))
            metric("First result", metrics.firstResultLatency.map { String(format: "%.2fs", $0.seconds) } ?? "–")
            metric("RTF", String(format: "%.2f", metrics.realTimeFactor))
            Spacer()
        }
        .padding(12)
        .talisman(cornerRadius: 16)
    }

    private func metric(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.footnote.weight(.semibold)).monospacedDigit()
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SpeakingStyle.allCases) { style in
                        Chip(title: style.title, systemImage: style.symbol, isSelected: settings.style == style, tint: KotodamaTheme.blossom) {
                            settings.style = style
                            if viewModel.savedTranscript != nil { Task { await viewModel.repolish() } }
                        }
                    }
                    Divider().frame(height: 20)
                    ForEach(UsageScenario.allCases) { scenario in
                        Chip(title: scenario.title, systemImage: scenario.symbol, isSelected: settings.scenario == scenario, tint: KotodamaTheme.paper) {
                            settings.scenario = scenario
                            if viewModel.savedTranscript != nil { Task { await viewModel.repolish() } }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .disabled(viewModel.isBusy)

            HStack {
                Spacer()
                orbButton
                Spacer()
            }
            .overlay(alignment: .trailing) {
                if viewModel.phase == .done || viewModel.errorMessage != nil {
                    Button {
                        viewModel.resetOutputs()
                        viewModel.errorMessage = nil
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .padding(.trailing, 28)
                    .accessibilityIdentifier("resetButton")
                }
            }
        }
        .padding(.vertical, 10)
        .background {
            LinearGradient(
                colors: [KotodamaTheme.inkBottom.opacity(0), KotodamaTheme.inkBottom.opacity(0.92), KotodamaTheme.inkBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private var orbButton: some View {
        let level = CGFloat(viewModel.isListening ? viewModel.capture.level : 0)
        return Button {
            viewModel.toggleListening()
        } label: {
            ZStack {
                Circle()
                    .stroke(KotodamaTheme.spirit.opacity(0.35), lineWidth: 2)
                    .frame(width: 80 + level * 50, height: 80 + level * 50)
                    .animation(.easeOut(duration: 0.12), value: level)
                Circle()
                    .fill(viewModel.isListening ? AnyShapeStyle(KotodamaTheme.recordingGradient) : AnyShapeStyle(KotodamaTheme.orbGradient))
                    .frame(width: 70, height: 70)
                    .shadow(color: (viewModel.isListening ? KotodamaTheme.vermilion : KotodamaTheme.spirit).opacity(0.6), radius: 16 + level * 20)
                if viewModel.isBusy, !viewModel.isListening {
                    ProgressView().tint(.white).controlSize(.large)
                } else {
                    Image(systemName: viewModel.isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 136, height: 136)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isBusy && !viewModel.isListening)
        .accessibilityLabel(viewModel.isListening ? "Stop listening" : "Start listening")
        .accessibilityIdentifier("orbButton")
    }
}
