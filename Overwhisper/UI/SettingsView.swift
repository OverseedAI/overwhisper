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

            if appState.debugModeEnabled {
                DebugSettingsView()
                    .tabItem {
                        Label("Debug", systemImage: "ladybug")
                    }
                    .environmentObject(appState)
            }
        }
        .tabViewStyle(.automatic)
        .frame(minWidth: 500, minHeight: 450)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Hotkeys") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Toggle")
                                .fontWeight(.medium)
                            Text("Press once to start, again to stop")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        HotkeyRecorderView(config: $appState.toggleHotkeyConfig, recorderId: "toggle")
                            .environmentObject(appState)
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Push-to-Talk")
                                .fontWeight(.medium)
                            Text("Hold to record, release to transcribe")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        HotkeyRecorderView(config: $appState.pushToTalkHotkeyConfig, recorderId: "pushToTalk")
                            .environmentObject(appState)
                    }
                }
            }

            Section("Overlay Position") {
                OverlayPositionGrid(selection: $appState.overlayPosition)
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

            Section("Advanced") {
                Toggle("Debug Mode", isOn: $appState.debugModeEnabled)
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
        .listStyle(.inset)
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
                HStack(spacing: 8) {
                    if isSelected {
                        Text("Active")
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                    }

                    Button(action: {
                        try? modelManager.deleteModel(model.rawValue)
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete model")
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
                .disabled(appState.currentlyDownloadingModel != nil)
            }
        }
        .padding(.vertical, 4)
    }
}

struct OutputSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var audioDeviceManager: AudioDeviceManager

    var body: some View {
        Form {
            Section {
                Picker("Microphone", selection: $appState.selectedInputDeviceUID) {
                    let defaultName = audioDeviceManager.defaultInputDeviceName
                    let defaultLabel = defaultName.map { "System Default (\($0))" } ?? "System Default"
                    Text(defaultLabel).tag("")

                    ForEach(audioDeviceManager.inputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Mute system audio while recording", isOn: $appState.muteSystemAudioWhileRecording)

                Toggle("Limit recording duration", isOn: $appState.recordingDurationLimitEnabled)

                if appState.recordingDurationLimitEnabled {
                    Stepper(
                        value: $appState.recordingDurationLimitSeconds,
                        in: 10...600,
                        step: 10
                    ) {
                        Text("Stop after \(appState.recordingDurationLimitSeconds) seconds")
                    }
                }
            } header: {
                Text("Recording")
            } footer: {
                Text("Note: This feature only works with built-in speakers. External audio interfaces may not support system volume control.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Feedback") {
                Toggle("Play sound when recording starts", isOn: $appState.playSoundOnStart)
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

struct OverlayPositionGrid: View {
    @Binding var selection: OverlayPosition

    var body: some View {
        VStack(spacing: 8) {
            // Top row
            HStack(spacing: 8) {
                ForEach(OverlayPosition.topRow) { position in
                    PositionCell(position: position, isSelected: selection == position)
                        .onTapGesture { selection = position }
                }
            }

            // Screen representation
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 2)

            // Bottom row
            HStack(spacing: 8) {
                ForEach(OverlayPosition.bottomRow) { position in
                    PositionCell(position: position, isSelected: selection == position)
                        .onTapGesture { selection = position }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct PositionCell: View {
    let position: OverlayPosition
    let isSelected: Bool

    private var label: String {
        switch position {
        case .topLeft: return "Top Left"
        case .topCenter: return "Top"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom"
        case .bottomRight: return "Bottom Right"
        }
    }

    var body: some View {
        Text(label)
            .font(.caption)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(6)
    }
}

struct DebugSettingsView: View {
    @EnvironmentObject var appState: AppState

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Header with clear button
            if !appState.debugLogs.isEmpty {
                HStack {
                    Spacer()
                    Button("Clear Logs") {
                        appState.clearDebugLogs()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()

                Divider()
            }

            if appState.debugLogs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No logs yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Debug logs will appear here as you use the app.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appState.debugLogs) { entry in
                        DebugLogRow(entry: entry, dateFormatter: dateFormatter)
                    }
                }
                .listStyle(.plain)
            }

            // System info footer
            Divider()
            HStack {
                Text("Model: \(appState.whisperModel.rawValue)")
                Spacer()
                Text("Engine: \(appState.transcriptionEngine.rawValue)")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.05))
        }
    }
}

struct DebugLogRow: View {
    let entry: DebugLogEntry
    let dateFormatter: DateFormatter

    private var levelColor: Color {
        switch entry.level {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.level.rawValue)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(levelColor)
                .cornerRadius(3)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.source)
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Text(dateFormatter.string(from: entry.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text(entry.message)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let appState = AppState()
    return SettingsView(modelManager: ModelManager(appState: appState))
        .environmentObject(appState)
        .environmentObject(AudioDeviceManager())
}
