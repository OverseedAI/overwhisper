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
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Text Replacements
            Section {
                TextEditor(text: $appState.textReplacements)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 60, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(6)
            } header: {
                Text("Text Replacements")
            } footer: {
                Text("One per line. Use \u{2192} or -> as separator. Case-insensitive.\nExample: Cloud Code \u{2192} Claude Code")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
    @State private var showDeleteConfirmation = false
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
                        showDeleteConfirmation = true
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
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .alert("Delete Model", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                try? modelManager.deleteModel(model.rawValue)
            }
        } message: {
            Text("Are you sure you want to delete \(model.displayName)? You'll need to download it again to use it.")
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

            Section("Feedback") {
                Toggle("Play sound when recording starts", isOn: $appState.playSoundOnStart)
                Toggle("Play sound on completion", isOn: $appState.playSoundOnCompletion)
                Toggle("Show notification on error", isOn: $appState.showNotificationOnError)
            }

            Section("Transcription History") {
                if appState.transcriptionHistory.isEmpty {
                    Text("No transcription yet")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(appState.transcriptionHistory.prefix(10)) { entry in
                                TranscriptionHistoryRow(entry: entry)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)

                    if appState.transcriptionHistory.count > 10 {
                        Text("Showing 10 of \(appState.transcriptionHistory.count) entries")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button("Clear History") {
                        appState.clearTranscriptionHistory()
                    }
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

enum DebugTab: String, CaseIterable, Identifiable {
    case sessions = "Sessions"
    case logs = "Logs"

    var id: String { rawValue }
}

struct DebugSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: DebugTab = .sessions

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedTab) {
                ForEach(DebugTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            switch selectedTab {
            case .sessions:
                DebugSessionsView()
                    .environmentObject(appState)
            case .logs:
                DebugLogsView()
                    .environmentObject(appState)
            }

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

struct DebugLogsView: View {
    @EnvironmentObject var appState: AppState

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            if !appState.debugLogs.isEmpty {
                HStack {
                    Spacer()
                    Button("Clear Logs") {
                        appState.clearDebugLogs()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

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
        }
    }
}

struct DebugSessionsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var player = DebugAudioPlayer()
    @State private var expandedSessionID: UUID?

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private var sessions: [TranscriptionDebugSession] {
        appState.debugSessionStore.sessions
    }

    var body: some View {
        VStack(spacing: 0) {
            if !sessions.isEmpty {
                HStack(spacing: 8) {
                    Text("\(sessions.count) recent session\(sessions.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.selectFile(
                            nil, inFileViewerRootedAtPath: appState.debugSessionStore.rootDirectory.path)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button("Clear All") {
                        player.stop()
                        appState.debugSessionStore.clear()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()
            }

            if sessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No sessions yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Each transcription you run while debug mode is on will be captured here, including its audio file.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sessions) { session in
                            DebugSessionRow(
                                session: session,
                                isExpanded: expandedSessionID == session.id,
                                player: player,
                                store: appState.debugSessionStore,
                                dateFormatter: dateFormatter,
                                dayFormatter: dayFormatter,
                                onToggle: {
                                    if expandedSessionID == session.id {
                                        expandedSessionID = nil
                                    } else {
                                        expandedSessionID = session.id
                                    }
                                }
                            )
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

struct DebugSessionRow: View {
    let session: TranscriptionDebugSession
    let isExpanded: Bool
    @ObservedObject var player: DebugAudioPlayer
    let store: DebugSessionStore
    let dateFormatter: DateFormatter
    let dayFormatter: DateFormatter
    let onToggle: () -> Void

    private var statusColor: Color { session.success ? .green : .red }

    private var audioURL: URL? { store.audioURL(for: session) }

    private var isCurrentlyPlaying: Bool {
        player.isPlaying && player.currentURL == audioURL
    }

    private var preview: String {
        if let error = session.errorMessage, !error.isEmpty { return error }
        let trimmed = session.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(empty result)" : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(session.engine)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text(session.model)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if session.usedCloudFallback {
                                Text("FALLBACK")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.orange)
                                    .cornerRadius(3)
                            }
                            Spacer()
                            Text(dateFormatter.string(from: session.timestamp))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Text(preview)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(session.success ? .primary : .red)
                            .lineLimit(isExpanded ? nil : 2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)

                        HStack(spacing: 12) {
                            MetricChip(icon: "waveform", label: formatDuration(session.recordingDurationSeconds))
                            MetricChip(icon: "timer", label: formatLatency(session.latencySeconds))
                            if let lang = session.language {
                                MetricChip(icon: "globe", label: lang)
                            }
                            if let size = session.audioFileSizeBytes {
                                MetricChip(icon: "doc", label: formatBytes(size))
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    if let url = audioURL {
                        HStack(spacing: 8) {
                            Button(action: { player.toggle(url: url) }) {
                                Image(systemName: isCurrentlyPlaying ? "pause.fill" : "play.fill")
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)

                            if isCurrentlyPlaying || player.currentURL == url {
                                ProgressView(value: player.duration > 0 ? player.currentTime / player.duration : 0)
                                    .progressViewStyle(.linear)
                                Text("\(formatTime(player.currentTime)) / \(formatTime(player.duration))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            } else if let dur = session.audioDurationSeconds {
                                Text(formatTime(dur))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }

                            Spacer()

                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            } label: {
                                Image(systemName: "folder")
                            }
                            .help("Reveal in Finder")
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    } else if session.audioFileName != nil {
                        Label("Audio file is missing", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        Label("No audio captured for this session", systemImage: "speaker.slash")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    DebugDetailsGrid(session: session, dayFormatter: dayFormatter)

                    HStack {
                        Spacer()
                        if !session.transcribedText.isEmpty {
                            Button("Copy Result") {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(session.transcribedText, forType: .string)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        Button(role: .destructive) {
                            if isCurrentlyPlaying { player.stop() }
                            store.delete(session)
                        } label: {
                            Text("Delete")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .background(Color.secondary.opacity(0.06))
            }
        }
    }

    private func formatLatency(_ seconds: Double) -> String {
        if seconds < 1 { return String(format: "%.0f ms", seconds * 1000) }
        return String(format: "%.2f s", seconds)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total >= 60 {
            return String(format: "%d:%02d", total / 60, total % 60)
        }
        return String(format: "%.1fs", seconds)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct MetricChip: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
        }
        .foregroundColor(.secondary)
    }
}

struct DebugDetailsGrid: View {
    let session: TranscriptionDebugSession
    let dayFormatter: DateFormatter

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            detail("When", "\(dayFormatter.string(from: session.timestamp)) at \(timeString)")
            detail("Engine", session.engine)
            detail("Model", session.model)
            detail("Recording", String(format: "%.2fs", session.recordingDurationSeconds))
            if let dur = session.audioDurationSeconds {
                detail("Audio", String(format: "%.2fs", dur))
            }
            detail("Latency", String(format: "%.3fs", session.latencySeconds))
            if let lang = session.language {
                detail("Language", lang)
            }
            if session.usedCloudFallback {
                detail("Fallback", "Yes")
            }
            if let size = session.audioFileSizeBytes {
                detail("File size", ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            }
            if let name = session.audioFileName {
                detail("File", name)
            }
        }
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: session.timestamp)
    }

    @ViewBuilder
    private func detail(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(minWidth: 70, alignment: .leading)
            Text(value)
                .font(.caption2)
                .foregroundColor(.primary)
                .textSelection(.enabled)
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
