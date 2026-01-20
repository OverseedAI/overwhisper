import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var modelManager: ModelManager

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .environmentObject(appState)

            ModelsSettingsView(modelManager: modelManager)
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
        .tabViewStyle(.automatic)
        .frame(minWidth: 500, minHeight: 450)
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

struct ModelsSettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var modelManager: ModelManager

    private var isUsingOpenAI: Bool {
        appState.transcriptionEngine == .openAI
    }

    private let languages = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("ko", "Korean"),
        ("ja", "Japanese"),
        ("zh", "Chinese"),
        ("ru", "Russian"),
        ("ar", "Arabic")
    ]

    var body: some View {
        List {
            // Language Selection
            Section {
                Picker("Language", selection: $appState.language) {
                    ForEach(languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
            } header: {
                Text("Language")
            } footer: {
                Text("Select the language you'll be speaking, or Auto-detect to let the model identify it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Cloud API Section
            Section {
                HStack {
                    Image(systemName: isUsingOpenAI ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isUsingOpenAI ? .accentColor : .primary)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("OpenAI Whisper API")
                                .fontWeight(isUsingOpenAI ? .semibold : .regular)
                            Image(systemName: "cloud.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                        }
                        Text("Cloud-based, requires API key")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if isUsingOpenAI {
                        Text("Active")
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.transcriptionEngine = .openAI
                }

                if isUsingOpenAI {
                    SecureField("API Key", text: $appState.openAIAPIKey)
                        .textFieldStyle(.roundedBorder)

                    if appState.openAIAPIKey.isEmpty {
                        Label("API key required", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            } header: {
                Text("Cloud")
            } footer: {
                Text("Audio is sent to OpenAI's servers for transcription.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Local Models - English
            Section {
                ForEach(WhisperModel.englishModels) { model in
                    ModelRowView(
                        model: model,
                        isDownloaded: appState.downloadedModels.contains(model.rawValue),
                        isSelected: !isUsingOpenAI && appState.whisperModel == model,
                        isDownloading: appState.currentlyDownloadingModel == model.rawValue,
                        downloadProgress: appState.modelDownloadProgress,
                        modelManager: modelManager
                    )
                    .environmentObject(appState)
                }
            } header: {
                Text("On-Device — English")
            } footer: {
                Text("Runs locally on your Mac. Optimized for English speech.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Local Models - Multilingual
            Section {
                ForEach(WhisperModel.multilingualModels) { model in
                    ModelRowView(
                        model: model,
                        isDownloaded: appState.downloadedModels.contains(model.rawValue),
                        isSelected: !isUsingOpenAI && appState.whisperModel == model,
                        isDownloading: appState.currentlyDownloadingModel == model.rawValue,
                        downloadProgress: appState.modelDownloadProgress,
                        modelManager: modelManager
                    )
                    .environmentObject(appState)
                }
            } header: {
                Text("On-Device — Multilingual")
            } footer: {
                Text("Runs locally. Supports 99+ languages including Korean, Japanese, Chinese, and more.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }
}

struct ModelRowView: View {
    @EnvironmentObject var appState: AppState
    let model: WhisperModel
    let isDownloaded: Bool
    let isSelected: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let modelManager: ModelManager

    var body: some View {
        HStack {
            // Selection indicator and model info - tappable area
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : (isDownloaded ? "circle" : "circle.dashed"))
                    .foregroundColor(isSelected ? .accentColor : (isDownloaded ? .primary : .secondary))
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(model.displayName)
                            .fontWeight(isSelected ? .semibold : .regular)

                        if isDownloaded {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                    }

                    Text(model.size)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isDownloaded && !isSelected {
                    appState.transcriptionEngine = .whisperKit
                    appState.whisperModel = model
                }
            }

            Spacer()

            if isDownloading {
                HStack(spacing: 8) {
                    ProgressView(value: downloadProgress)
                        .frame(width: 60)
                    Text("\(Int(downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 35)
                }
            } else if isDownloaded {
                if isSelected {
                    Text("Active")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                }
            } else {
                Button(action: {
                    Task {
                        try? await modelManager.downloadModel(model.rawValue)
                    }
                }) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .disabled(appState.isDownloadingModel)
            }
        }
        .padding(.vertical, 4)
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
    let appState = AppState()
    return SettingsView(modelManager: ModelManager(appState: appState))
        .environmentObject(appState)
}
