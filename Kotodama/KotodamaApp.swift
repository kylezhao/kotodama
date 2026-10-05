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
    }
}
