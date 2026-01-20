import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .environmentObject(appState)

            TranscriptionSettingsView()
                .tabItem {
                    Label("Transcription", systemImage: "waveform")
                }
                .environmentObject(appState)

            OutputSettingsView()
                .tabItem {
                    Label("Output", systemImage: "text.cursor")
                }
                .environmentObject(appState)
        }
        .frame(width: 450, height: 350)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Hotkey") {
                HStack {
                    Text("Trigger:")
                    Spacer()
                    HotkeyRecorderView(config: $appState.hotkeyConfig)
                }

                Picker("Mode:", selection: $appState.recordingMode) {
                    ForEach(RecordingMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if appState.recordingMode == .pushToTalk {
                    Text("Hold the hotkey to record, release to transcribe")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Press the hotkey once to start, again to stop")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Overlay") {
                Picker("Position:", selection: $appState.overlayPosition) {
                    ForEach(OverlayPosition.allCases) { position in
                        Text(position.rawValue).tag(position)
                    }
                }
            }

            Section("Startup") {
                Toggle("Start at login", isOn: $appState.startAtLogin)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Check Accessibility Permission") {
                        checkAccessibilityPermission()
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

struct TranscriptionSettingsView: View {
    @EnvironmentObject var appState: AppState

    private let languages = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("pl", "Polish"),
        ("ru", "Russian"),
        ("zh", "Chinese"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("ar", "Arabic")
    ]

    var body: some View {
        Form {
            Section("Engine") {
                Picker("Engine:", selection: $appState.transcriptionEngine) {
                    ForEach(TranscriptionEngineType.allCases) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }
            }

            if appState.transcriptionEngine == .whisperKit {
                Section("WhisperKit Settings") {
                    Picker("Model:", selection: $appState.whisperModel) {
                        ForEach(WhisperModel.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }

                    if appState.isDownloadingModel {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Downloading model...")
                                .foregroundColor(.secondary)
                        }
                    } else if appState.isModelDownloaded {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Model ready")
                                .foregroundColor(.secondary)
                        }
                    }

                    Text("Larger models are more accurate but slower. The '.en' variants are optimized for English only.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Language") {
                Picker("Language:", selection: $appState.language) {
                    ForEach(languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
            }

            Section("Cloud Fallback") {
                Toggle("Enable cloud fallback", isOn: $appState.enableCloudFallback)

                if appState.enableCloudFallback || appState.transcriptionEngine == .openAI {
                    SecureField("OpenAI API Key:", text: $appState.openAIAPIKey)
                        .textFieldStyle(.roundedBorder)

                    Text("Your API key is stored securely in the Keychain")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct OutputSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Feedback") {
                Toggle("Play sound on completion", isOn: $appState.playSoundOnCompletion)
                Toggle("Show notification on error", isOn: $appState.showNotificationOnError)
            }

            Section("Last Transcription") {
                if appState.lastTranscription.isEmpty {
                    Text("No transcription yet")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    Text(appState.lastTranscription)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                }

                if let error = appState.lastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(error)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How it works:")
                        .font(.headline)
                    Text("1. Press your hotkey to start recording")
                    Text("2. Speak clearly into your microphone")
                    Text("3. Release (push-to-talk) or press again (toggle) to stop")
                    Text("4. Text is automatically typed at your cursor")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
