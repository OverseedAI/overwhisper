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

            SmartFeaturesSettingsView()
                .tabItem {
                    Label("Smart", systemImage: "wand.and.stars")
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
    @State private var showResetConfirmation = false

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

                Button("Reset All Settings to Defaults") {
                    showResetConfirmation = true
                }
                .foregroundColor(.red)
            }
            .alert("Reset to Defaults", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    appState.resetToDefaults()
                }
            } message: {
                Text("This will reset all settings including hotkeys to their default values. Your API key and transcription history will be preserved.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Thanks for using Overwhisper! For issues and inquiries, please visit:")
                        .font(.callout)
                    Link("github.com/OverseedAI/overwhisper", destination: URL(string: "https://github.com/OverseedAI/overwhisper")!)
                }
                .padding(.vertical, 4)

                HStack {
                    Text("Company Website")
                        .foregroundColor(.secondary)
                    Spacer()
                    Link("overseed.ai", destination: URL(string: "https://overseed.ai/")!)
                }

                HStack {
                    Text("X (Twitter)")
                        .foregroundColor(.secondary)
                    Spacer()
                    Link("@_halshin", destination: URL(string: "https://x.com/_halshin")!)
                }

                HStack {
                    Text("LinkedIn")
                        .foregroundColor(.secondary)
                    Spacer()
                    Link("Hal Shin", destination: URL(string: "https://www.linkedin.com/in/halshin/")!)
                }

                HStack {
                    Text("YouTube")
                        .foregroundColor(.secondary)
                    Spacer()
                    Link("@halshin_software", destination: URL(string: "https://www.youtube.com/@halshin_software")!)
                }
            } header: {
                Text("Support")
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
    @State private var showModelSelection = false

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
            // Current Model - Visual indicator only
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("Current Engine:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            if appState.transcriptionEngine == .whisperKit {
                                Label("Local", systemImage: "cpu")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                            } else {
                                Label("Cloud", systemImage: "cloud.fill")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        if appState.transcriptionEngine == .whisperKit {
                            Text(appState.whisperModel.displayName)
                                .font(.callout)
                                .foregroundColor(.primary)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            // Language Selection
            Section {
                Picker("Language", selection: $appState.language) {
                    ForEach(languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }

                Toggle("Translate to English", isOn: $appState.translateToEnglish)
            } header: {
                Text("Language")
            } footer: {
                if appState.translateToEnglish {
                    Text("Audio will be translated to English. Requires a multilingual model.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Select the language you'll be speaking, or Auto-detect to let the model identify it.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Custom Vocabulary
            Section {
                TextEditor(text: $appState.customVocabulary)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 60, maxHeight: 100)
                    .scrollContentBackground(.hidden)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(6)
            } header: {
                Text("Custom Vocabulary")
            } footer: {
                Text("Enter names, acronyms, or terms that get misspelled. Works best as a natural phrase, e.g. \"Meeting with Hal Shin at Overseed AI about WhisperKit.\"")
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

            // Local Model Section - Always visible
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appState.whisperModel.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(appState.downloadedModels.contains(appState.whisperModel.rawValue) ? "Downloaded" : "Not downloaded")
                            .font(.caption)
                            .foregroundColor(appState.downloadedModels.contains(appState.whisperModel.rawValue) ? .green : .orange)
                    }
                    
                    Spacer()
                    
                    Button("Change Model...") {
                        showModelSelection = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Local Model")
            } footer: {
                Text("The local model is used when Cloud is not selected.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(.inset)
        .sheet(isPresented: $showModelSelection) {
            ModelSelectionView(modelManager: modelManager)
                .environmentObject(appState)
        }
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

            Section("Output") {
                Toggle("Copy text to clipboard", isOn: $appState.copyToClipboard)
                Text("Keep transcribed text in clipboard for manual pasting")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Feedback") {
                Toggle("Play sound when recording starts", isOn: $appState.playSoundOnStart)
                Toggle("Play sound on completion", isOn: $appState.playSoundOnCompletion)
                Toggle("Show notification on error", isOn: $appState.showNotificationOnError)
            }

            Section("Transcription History") {
                TranscriptionHistoryView()
                    .frame(height: 280)
            }
            
            Section("Auto-Save Settings") {
                Toggle("Auto-save transcriptions to file", isOn: $appState.autoSaveToFile)
                
                if appState.autoSaveToFile {
                    HStack {
                        Text("Save Location:")
                        Spacer()
                        Text(appState.autoSaveDirectory.isEmpty ? "Documents folder" : appState.autoSaveDirectory)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Button("Choose Folder...") {
                        chooseAutoSaveDirectory()
                    }
                    .buttonStyle(.bordered)
                    
                    Text("Files are saved as Overwhisper_YYYY-MM-DD.txt")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
    
    private func chooseAutoSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Choose a folder to save transcription logs"
        
        panel.begin { result in
            if result == .OK, let url = panel.url {
                appState.autoSaveDirectory = url.path
            }
        }
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

struct TranscriptionHistoryRow: View {
    let entry: TranscriptionHistoryEntry

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(Self.dateFormatter.string(from: entry.timestamp))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
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

struct SmartFeaturesSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Form {
            Section("Auto-Stop Recording") {
                Toggle("Stop on silence detection", isOn: $appState.autoDetectSilence)
                
                if appState.autoDetectSilence {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Silence timeout:")
                            Spacer()
                            Text("\(Int(appState.silenceTimeoutSeconds)) seconds")
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(
                            value: $appState.silenceTimeoutSeconds,
                            in: 1...10,
                            step: 0.5
                        )
                    }
                    .padding(.vertical, 4)
                }
                
                Text("Automatically stop recording after the specified period of silence.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Voice Processing") {
                Toggle("Voice Activity Detection (VAD)", isOn: $appState.voiceActivityDetection)
                
                Text("Filter out background noise and only transcribe when speech is detected.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Transcription Options") {
                Toggle("Auto-punctuation", isOn: $appState.autoPunctuation)
                
                Text("Automatically add punctuation to transcriptions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                Toggle("Profanity filter", isOn: $appState.profanityFilter)
                
                Text("Mask inappropriate language in transcriptions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("These features use additional processing and may affect transcription speed.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
        .environmentObject(AudioDeviceManager())
}
