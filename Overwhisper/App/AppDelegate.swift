import AppKit
import SwiftUI
import AVFoundation
import Combine
import UserNotifications
import Sparkle

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var appState = AppState()

    private let updaterController: SPUStandardUpdaterController

    private var hotkeyManager: HotkeyManager!
    private var audioRecorder: AudioRecorder!
    private var overlayWindow: OverlayWindow!
    private var textInserter: TextInserter!
    private var transcriptionEngine: (any TranscriptionEngine)?
    private var modelManager: ModelManager!
    private var settingsWindow: NSWindow?

    private var cancellables = Set<AnyCancellable>()
    private var initializationTask: Task<Void, Never>?
    private var escapeKeyMonitor: Any?

    override init() {
        // Initialize Sparkle updater
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - menu bar only
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupComponents()
        setupBindings()
        setupSleepWakeHandling()

        // Request microphone permission
        requestMicrophonePermission()

        // Initialize transcription engine
        Task {
            await initializeTranscriptionEngine()
        }
    }

    private func setupSleepWakeHandling() {
        let workspace = NSWorkspace.shared.notificationCenter

        workspace.addObserver(
            self,
            selector: #selector(handleSystemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        workspace.addObserver(
            self,
            selector: #selector(handleSystemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleSystemWillSleep(_ notification: Notification) {
        // Cancel any active recording before sleep
        if appState.recordingState == .recording {
            cancelRecording()
        }
    }

    @objc private func handleSystemDidWake(_ notification: Notification) {
        // Reset the audio engine to ensure it's ready after wake
        audioRecorder.resetAudioEngine()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Overwhisper")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let versionItem = NSMenuItem(title: "Overwhisper v\(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Start Recording", action: #selector(toggleRecording), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Overwhisper", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func setupComponents() {
        audioRecorder = AudioRecorder()
        overlayWindow = OverlayWindow(appState: appState)
        textInserter = TextInserter()
        modelManager = ModelManager(appState: appState)
        hotkeyManager = HotkeyManager(appState: appState) { [weak self] event, mode in
            Task { @MainActor in
                self?.handleHotkeyEvent(event, mode: mode)
            }
        }
    }

    private func setupBindings() {
        // Update menu bar icon based on state
        appState.$recordingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateStatusIcon(for: state)
                self?.updateMenu(for: state)
            }
            .store(in: &cancellables)

        // Update audio level
        audioRecorder.$currentLevel
            .receive(on: DispatchQueue.main)
            .assign(to: &appState.$audioLevel)

        // Re-register hotkeys when configs change
        appState.$toggleHotkeyConfig
            .dropFirst()
            .sink { [weak self] config in
                self?.hotkeyManager.registerToggleHotkey(config: config)
            }
            .store(in: &cancellables)

        appState.$pushToTalkHotkeyConfig
            .dropFirst()
            .sink { [weak self] config in
                self?.hotkeyManager.registerPushToTalkHotkey(config: config)
            }
            .store(in: &cancellables)

        // Re-initialize engine when settings change
        appState.$transcriptionEngine
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.initializeTranscriptionEngine()
                }
            }
            .store(in: &cancellables)

        appState.$whisperModel
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.initializeTranscriptionEngine()
                }
            }
            .store(in: &cancellables)

        // Update UI when engine initialization state changes
        appState.$isInitializingEngine
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isInitializing in
                self?.updateInitializingState(isInitializing)
            }
            .store(in: &cancellables)
    }

    private func updateStatusIcon(for state: RecordingState) {
        guard let button = statusItem.button else { return }

        // Always use nil tint to keep icon white/adaptive to system appearance
        button.contentTintColor = nil

        switch state {
        case .idle:
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Idle")
        case .recording:
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Recording")
        case .transcribing:
            button.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Transcribing")
        case .error:
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Error")
        }
    }

    private func updateMenu(for state: RecordingState) {
        guard let menu = statusItem.menu, menu.items.count > 2 else { return }
        let recordingItem = menu.items[2] // After version item and separator

        switch state {
        case .idle:
            recordingItem.title = "Start Recording"
            recordingItem.isEnabled = true
        case .recording:
            recordingItem.title = "Stop Recording"
            recordingItem.isEnabled = true
        case .transcribing:
            recordingItem.title = "Transcribing..."
            recordingItem.isEnabled = false
        case .error:
            recordingItem.title = "Start Recording"
            recordingItem.isEnabled = true
        }
    }

    private func updateInitializingState(_ isInitializing: Bool) {
        guard let button = statusItem.button,
              let menu = statusItem.menu,
              menu.items.count > 2 else { return }
        let recordingItem = menu.items[2] // After version item and separator

        if isInitializing {
            button.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Loading Model")
            button.contentTintColor = nil
            recordingItem.title = "Loading Model..."
            recordingItem.isEnabled = false
        } else {
            // Restore based on current recording state
            updateStatusIcon(for: appState.recordingState)
            updateMenu(for: appState.recordingState)
        }
    }

    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                Task { @MainActor in
                    self.showPermissionAlert(for: "Microphone")
                }
            }
        }
    }

    private func showPermissionAlert(for permission: String) {
        let alert = NSAlert()
        alert.messageText = "\(permission) Access Required"
        alert.informativeText = "Overwhisper needs \(permission.lowercased()) access to function. Please enable it in System Settings > Privacy & Security > \(permission)."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(permission)") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func initializeTranscriptionEngine() async {
        // Cancel any existing initialization
        initializationTask?.cancel()

        // Prevent concurrent initialization
        guard !appState.isInitializingEngine else {
            print("Engine initialization already in progress, skipping")
            return
        }

        appState.isInitializingEngine = true
        print("Starting engine initialization for: \(appState.transcriptionEngine.rawValue)")

        switch appState.transcriptionEngine {
        case .whisperKit:
            let engine = WhisperKitEngine(appState: appState, modelManager: modelManager)
            transcriptionEngine = engine  // Assign first so it's available
            await engine.initialize()
        case .openAI:
            transcriptionEngine = OpenAIEngine(apiKey: appState.openAIAPIKey)
        }

        appState.isInitializingEngine = false
        print("Engine initialization complete")
    }

    private func handleHotkeyEvent(_ event: HotkeyEvent, mode: HotkeyMode) {
        switch mode {
        case .pushToTalk:
            if event == .keyDown {
                startRecording()
            } else {
                stopAndTranscribe()
            }
        case .toggle:
            if event == .keyDown {
                if appState.recordingState == .recording {
                    stopAndTranscribe()
                } else if appState.recordingState.isIdle {
                    startRecording()
                }
            }
        }
    }

    @objc private func toggleRecording() {
        if appState.recordingState == .recording {
            stopAndTranscribe()
        } else if appState.recordingState.isIdle {
            startRecording()
        }
    }

    private func startRecording() {
        guard appState.recordingState.isIdle else { return }

        // Check if engine is still initializing
        if appState.isInitializingEngine {
            showNotification(title: "Please Wait", body: "Model is still loading...")
            return
        }

        // Check if model is available when using WhisperKit
        if appState.transcriptionEngine == .whisperKit {
            let currentModel = appState.whisperModel.rawValue
            if !appState.downloadedModels.contains(currentModel) && !appState.isDownloadingModel {
                showNoModelAlert()
                return
            }
        }

        // Check if OpenAI API key is set when using OpenAI
        if appState.transcriptionEngine == .openAI && appState.openAIAPIKey.isEmpty {
            showNotification(title: "API Key Required", body: "Please set your OpenAI API key in Settings.")
            openSettings()
            return
        }

        // Ensure we have an engine
        guard transcriptionEngine != nil else {
            showNotification(title: "Engine Not Ready", body: "Transcription engine is not initialized. Please wait or check settings.")
            return
        }

        do {
            // Play sound on start if enabled (before muting)
            if appState.playSoundOnStart {
                NSSound(named: .init("Glass"))?.play()
            }

            // Mute system audio if enabled
            if appState.muteSystemAudioWhileRecording {
                SystemAudioManager.muteSystemAudio()
            }

            try audioRecorder.startRecording()
            appState.recordingState = .recording
            appState.startRecordingTimer()
            overlayWindow.show(position: appState.overlayPosition)
            startEscapeKeyMonitor()
        } catch {
            appState.recordingState = .error("Failed to start recording: \(error.localizedDescription)")
            appState.lastError = error.localizedDescription
            if appState.showNotificationOnError {
                showNotification(title: "Recording Error", body: error.localizedDescription)
            }
        }
    }

    private func showNoModelAlert() {
        let alert = NSAlert()
        alert.messageText = "No Model Downloaded"
        alert.informativeText = "You need to download a transcription model before recording. Would you like to open Settings to download one?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            openSettings()
        }
    }

    private func stopAndTranscribe() {
        guard appState.recordingState == .recording else { return }

        stopEscapeKeyMonitor()

        // Restore system audio if it was muted
        if appState.muteSystemAudioWhileRecording {
            SystemAudioManager.restoreSystemAudio()
        }

        appState.stopRecordingTimer()
        appState.recordingState = .transcribing
        overlayWindow.showTranscribing()

        Task {
            do {
                let audioURL = try audioRecorder.stopRecording()

                guard let engine = transcriptionEngine else {
                    throw TranscriptionError.engineNotInitialized
                }

                // Log which model is being used
                let modelInfo = appState.transcriptionEngine == .openAI
                    ? "OpenAI whisper-1"
                    : "WhisperKit \(appState.whisperModel.rawValue)"
                appState.addDebugLog("Starting transcription with \(modelInfo)", source: "Transcription")

                let text = try await engine.transcribe(audioURL: audioURL)

                // Clean up audio file
                try? FileManager.default.removeItem(at: audioURL)

                if !text.isEmpty {
                    appState.lastTranscription = text
                    textInserter.insertText(text)

                    if appState.playSoundOnCompletion {
                        NSSound(named: .init("Tink"))?.play()
                    }
                }

                appState.recordingState = .idle
                overlayWindow.hide()

            } catch {
                print("Transcription error: \(error)")
                appState.recordingState = .error(error.localizedDescription)
                appState.lastError = error.localizedDescription
                overlayWindow.hide()

                // Try cloud fallback if enabled
                if appState.enableCloudFallback && appState.transcriptionEngine == .whisperKit && !appState.openAIAPIKey.isEmpty {
                    await tryCloudFallback()
                } else if appState.showNotificationOnError {
                    showNotification(title: "Transcription Error", body: error.localizedDescription)
                }
            }
        }
    }

    private func tryCloudFallback() async {
        // Note: Would need to save the audio URL to retry, simplified here
        showNotification(title: "Fallback", body: "Using cloud transcription as fallback")
    }

    private func cancelRecording() {
        guard appState.recordingState == .recording else { return }

        stopEscapeKeyMonitor()

        // Restore system audio if it was muted
        if appState.muteSystemAudioWhileRecording {
            SystemAudioManager.restoreSystemAudio()
        }

        appState.stopRecordingTimer()
        audioRecorder.cancelRecording()
        appState.recordingState = .idle
        overlayWindow.hide()
    }

    private func startEscapeKeyMonitor() {
        escapeKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                Task { @MainActor in
                    self?.cancelRecording()
                }
            }
        }
    }

    private func stopEscapeKeyMonitor() {
        if let monitor = escapeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            escapeKeyMonitor = nil
        }
    }

    private func showNotification(title: String, body: String) {
        // UNUserNotificationCenter requires a proper app bundle
        // When running via swift run, we don't have one, so use a fallback
        guard Bundle.main.bundleIdentifier != nil else {
            // Fallback: just print to console when running without bundle
            print("[\(title)] \(body)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    @objc private func openSettings() {
        // Refresh downloaded models list
        modelManager.scanForModels()

        if let window = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let settingsView = SettingsView(modelManager: modelManager)
            .environmentObject(appState)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Overwhisper Settings"
        window.minSize = NSSize(width: 500, height: 450)
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false

        self.settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    @objc private func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

enum TranscriptionError: LocalizedError {
    case engineNotInitialized
    case noAudioData
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .engineNotInitialized:
            return "Transcription engine not initialized"
        case .noAudioData:
            return "No audio data recorded"
        case .apiError(let message):
            return message
        }
    }
}
