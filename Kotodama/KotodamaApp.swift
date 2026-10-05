//
//  KotodamaApp.swift
//  Kotodama
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import SwiftData
import SwiftUI
import Translation

@main
struct KotodamaApp: App {
    @State private var settings = AppSettings()
    @State private var translationCoordinator = AppleTranslationCoordinator()
    @State private var speechPlayer: SpeechPlayer
    @State private var spiritFont = SpiritFont()

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _speechPlayer = State(initialValue: SpeechPlayer(settings: settings))
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Transcript.self, TranslationResult.self])
        let isUITesting = CommandLine.arguments.contains("-ui-testing")
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView(settings: settings, translationCoordinator: translationCoordinator)
                .environment(settings)
                .environment(translationCoordinator)
                .environment(speechPlayer)
                .environment(spiritFont)
                .preferredColorScheme(.dark)
                .tint(KotodamaTheme.paper)
        }
        .modelContainer(sharedModelContainer)
    }
}

private struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    let settings: AppSettings
    let translationCoordinator: AppleTranslationCoordinator

    var body: some View {
        TabView {
            Tab("Speak", systemImage: "waveform") {
                SpeakView(settings: settings, modelContext: modelContext, translationCoordinator: translationCoordinator)
            }
            Tab("History", systemImage: "scroll") {
                HistoryView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        // Apple's Translation framework hands out sessions only through this modifier, so the
        // coordinator drives it from here for the whole app.
        .translationTask(translationCoordinator.configuration) { session in
            await translationCoordinator.handle(session)
        }
        .onAppear { seedHistoryIfRequested() }
    }

    /// `-seed-history` fills the (in-memory) store with one finished transcript so UI tests can
    /// exercise the history and detail screens without a microphone or network.
    private func seedHistoryIfRequested() {
        guard CommandLine.arguments.contains("-seed-history") else { return }
        let transcript = Transcript(
            languageID: "zh-CN",
            rawText: "你能听得懂我说的话吗？",
            style: .natural,
            scenario: .notes,
            recognitionMode: .onDevice,
            recognizerName: "Apple Speech",
            recognizerModelID: "SpeechTranscriber (on-device)",
            audioDuration: 8.3,
            recognitionSeconds: 8.9,
            firstResultSeconds: 2.55
        )
        transcript.title = "听力测试"
        transcript.polishedText = "你能听得懂我说的话吗？"
        transcript.summary = "询问对方是否能听懂自己说的话。"
        transcript.refinerName = "Apple Intelligence"
        transcript.refinerModelID = "SystemLanguageModel (on-device)"
        transcript.refinementSeconds = 2.12
        modelContext.insert(transcript)
        for (target, text) in [("en", "Can you understand what I'm saying?"), ("ja", "私が話していることを理解できますか？")] {
            let translation = TranslationResult(targetLanguageID: target, text: text, translatorName: "Apple Translate", translatorModelID: "Translation framework (on-device)", seconds: 0.4, transcript: transcript)
            modelContext.insert(translation)
            transcript.translations.append(translation)
        }
        try? modelContext.save()
    }
}
