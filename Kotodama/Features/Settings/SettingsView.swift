//
//  SettingsView.swift
//  Kotodama
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import FoundationModels
import SwiftUI
import Translation

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var onDeviceStatus: RecognizerAvailability = .ready
    @State private var onDeviceModelID = ""
    @State private var intelligenceReady = false
    @State private var translationStatuses: [String: LanguageAvailability.Status] = [:]

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Picker("Recognition runs", selection: $settings.recognitionMode) {
                        ForEach(RecognitionMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbol).tag(mode)
                        }
                    }
                    Text(settings.recognitionMode.subtitle).font(.footnote).foregroundStyle(.secondary)
                    HStack {
                        Label("Speech model for \(settings.sourceLanguage.name)", systemImage: "waveform")
                        Spacer()
                        statusLabel
                    }
                    if !onDeviceModelID.isEmpty {
                        Text(onDeviceModelID).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Speech recognition")
                }

                Section {
                    Picker("Polishing and translation", selection: $settings.intelligenceMode) {
                        ForEach(IntelligenceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    HStack {
                        Label("Apple Intelligence", systemImage: "apple.intelligence")
                        Spacer()
                        Label(intelligenceReady ? "Ready" : "Unavailable", systemImage: intelligenceReady ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(intelligenceReady ? .green : KotodamaTheme.vermilion)
                    }
                    Picker("Cloud model", selection: $settings.cloudModel) {
                        ForEach(CloudModel.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    SecureField("Anthropic API key", text: $settings.apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if settings.hasAPIKey {
                        Label("Stored in the keychain on this device", systemImage: "lock.fill").font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Intelligence")
                } footer: {
                    Text("Automatic uses Apple Intelligence on device when it is available, then Claude if an API key is set, and finally built-in clean-up rules. Translation prefers Apple Translate on device and falls back to Claude.")
                }

                Section {
                    Toggle("Translate automatically", isOn: $settings.autoTranslate)
                    ForEach(TargetLanguage.all) { target in
                        Button {
                            settings.toggleTarget(target)
                        } label: {
                            HStack {
                                Text("\(target.flag) \(target.name)")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if let status = translationStatuses[target.id] {
                                    Text(statusText(status)).font(.caption2).foregroundStyle(.secondary)
                                }
                                Image(systemName: settings.targetLanguageIDs.contains(target.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(settings.targetLanguageIDs.contains(target.id) ? KotodamaTheme.paper : .secondary)
                            }
                        }
                    }
                } header: {
                    Text("Translate into")
                } footer: {
                    Text("Apple Translate downloads language packs on first use.")
                }

                Section {
                    Toggle("Show model metrics", isOn: $settings.showMetrics)
                } header: {
                    Text("Display")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    Text("Copyright © 2026 Kyle Zhao. All rights reserved.").font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("About")
                }
            }
            .scrollContentBackground(.hidden)
            .background(SpiritFieldBackground())
            .navigationTitle("Settings")
            .task(id: "\(settings.sourceLanguageID)-\(settings.recognitionMode.rawValue)-\(settings.targetLanguageIDs.joined())") {
                await refresh()
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch onDeviceStatus {
        case .ready: Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .needsDownload: Label("Needs download", systemImage: "arrow.down.circle").foregroundStyle(KotodamaTheme.paper)
        case .unavailable: Label("Unavailable", systemImage: "xmark.circle.fill").foregroundStyle(KotodamaTheme.vermilion)
        }
    }

    private func statusText(_ status: LanguageAvailability.Status) -> String {
        switch status {
        case .installed: String(localized: "installed")
        case .supported: String(localized: "download on first use")
        case .unsupported: String(localized: "cloud only")
        @unknown default: ""
        }
    }

    private func refresh() async {
        let recognizer: any SpeechRecognizer = settings.recognitionMode == .onDevice ? AppleOnDeviceRecognizer() : AppleCloudRecognizer()
        onDeviceStatus = await recognizer.availability(for: settings.sourceLanguage)
        onDeviceModelID = await recognizer.descriptor(for: settings.sourceLanguage).modelID
        intelligenceReady = SystemLanguageModel.default.isAvailable
        var statuses: [String: LanguageAvailability.Status] = [:]
        for target in TargetLanguage.all {
            statuses[target.id] = await LanguageAvailability().status(from: settings.sourceLanguage.language, to: target.language)
        }
        translationStatuses = statuses
    }
}
