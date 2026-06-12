import AppKit
import SwiftUI
import AVFoundation
import Combine
import UserNotifications
import Sparkle

enum AppEnvironment {
    /// True when running outside a real .app bundle (swift run / bare .build binary).
    static let isDevBuild = Bundle.main.bundleIdentifier == nil
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var appState = AppState()

    private let updaterController: SPUStandardUpdaterController

    private var hotkeyManager: HotkeyManager!
    private var audioRecorder: AudioRecorder!
    private var audioDeviceManager: AudioDeviceManager!
    private var overlayWindow: OverlayWindow!
    private var textInserter: TextInserter!
    private var transcriptionEngine: (any TranscriptionEngine)?
    private var modelManager: ModelManager!
    private var settingsWindow: NSWindow?
    private var recordingMenuItem: NSMenuItem?
    private var engineMenuItem: NSMenuItem?
    private var errorSeparatorItem: NSMenuItem?
    private var errorMenuItem: NSMenuItem?
    private var retryMenuItem: NSMenuItem?
    private var recentMenu: NSMenu?
    private var copyLastMenuItem: NSMenuItem?
    private var lastFailedSession: TranscriptionDebugSession?
    private var onboardingWindow: NSWindow?
    private var recordingLimitTimer: Timer?

    private var cancellables = Set<AnyCancellable>()
    private var initializationTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var escapeKeyMonitor: Any?
    private var errorResetTimer: Timer?

    // Tap-vs-hold on the toggle hotkey: tap toggles, holding past the
    // threshold acts as push-to-talk (release stops and transcribes).
    private static let tapHoldThreshold: TimeInterval = 0.5
    private var toggleKeyDownAt: Date?
    private var toggleKeyDownStartedRecording = false
    private var iconAnimationTimer: Timer?
    private var iconAnimationFrame: Int = 0
    private var isLoadingAnimation: Bool = false

    override init() {
        // Sparkle can't start without a real app bundle — starting it from a
        // bare dev binary throws up a "failed to start updater" alert.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: !AppEnvironment.isDevBuild,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Install crash reporter first
        CrashReporter.shared.install()

        // Hide dock icon - menu bar only
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupComponents()
        setupBindings()
        setupSleepWakeHandling()
        setupEscapeKeyMonitor()

        showOnboardingIfNeeded()

        launchEngineInitialization()
    }

    private func launchEngineInitialization() {
        initializationTask = Task {
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
            button.image = MenuBarIcon.create()
        }

        let menu = NSMenu()
        // Enabled state is managed manually throughout (recording/transcribing/loading).
        menu.autoenablesItems = false

        let versionTitle: String
        if AppEnvironment.isDevBuild {
            versionTitle = "Overwhisper · dev build"
        } else {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            versionTitle = "Overwhisper v\(version)"
        }
        let versionItem = NSMenuItem(title: versionTitle, action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let builtByItem = NSMenuItem(title: "Built by Hal Shin", action: nil, keyEquivalent: "")
        builtByItem.isEnabled = false
        menu.addItem(builtByItem)

        menu.addItem(NSMenuItem.separator())

        let engineItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        engineItem.isEnabled = false
        menu.addItem(engineItem)
        self.engineMenuItem = engineItem
        updateEngineMenuItem()

        menu.addItem(NSMenuItem.separator())

        let recordingItem = NSMenuItem(title: "Start Recording", action: #selector(toggleRecording), keyEquivalent: "")
        recordingItem.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Record")
        menu.addItem(recordingItem)
        self.recordingMenuItem = recordingItem

        let retryItem = NSMenuItem(title: "Retry Last Transcription", action: #selector(retryLastTranscription), keyEquivalent: "")
        retryItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Retry")
        retryItem.isHidden = true
        menu.addItem(retryItem)
        self.retryMenuItem = retryItem

        menu.addItem(NSMenuItem.separator())

        let recentItem = NSMenuItem(title: "Recent Transcriptions", action: nil, keyEquivalent: "")
        recentItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Recent")
        let recentSubmenu = NSMenu()
        recentSubmenu.autoenablesItems = false
        recentItem.submenu = recentSubmenu
        menu.addItem(recentItem)
        self.recentMenu = recentSubmenu

        let copyLastItem = NSMenuItem(title: "Copy Last Transcription", action: #selector(copyLastTranscription), keyEquivalent: "")
        copyLastItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")
        menu.addItem(copyLastItem)
        self.copyLastMenuItem = copyLastItem

        let errorSeparator = NSMenuItem.separator()
        errorSeparator.isHidden = true
        menu.addItem(errorSeparator)
        self.errorSeparatorItem = errorSeparator

        let errorItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        errorItem.isEnabled = false
        errorItem.isHidden = true
        menu.addItem(errorItem)
        self.errorMenuItem = errorItem

        menu.addItem(NSMenuItem.separator())

        if !AppEnvironment.isDevBuild {
            let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
            updateItem.image = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: "Update")
            menu.addItem(updateItem)
        }

        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Overwhisper", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = menu

        rebuildRecentMenu(with: appState.transcriptionHistory)
    }

    private func rebuildRecentMenu(with history: [TranscriptionHistoryEntry]) {
        guard let recentMenu else { return }
        recentMenu.removeAllItems()

        let entries = history.prefix(10)
        if entries.isEmpty {
            let empty = NSMenuItem(title: "No transcriptions yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
        } else {
            for entry in entries {
                let item = NSMenuItem(title: Self.menuPreview(for: entry.text), action: #selector(copyHistoryEntry(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry.text
                item.toolTip = entry.text
                recentMenu.addItem(item)
            }
        }

        copyLastMenuItem?.isEnabled = !history.isEmpty
    }

    private static func menuPreview(for text: String) -> String {
        let collapsed = text.replacingOccurrences(of: "\n", with: " ")
        return collapsed.count > 60 ? "\(collapsed.prefix(57))..." : collapsed
    }

    @objc private func copyHistoryEntry(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        copyToClipboard(text)
    }

    @objc private func copyLastTranscription() {
        guard !appState.lastTranscription.isEmpty else { return }
        copyToClipboard(appState.lastTranscription)
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func setupComponents() {
        audioRecorder = AudioRecorder()
        audioDeviceManager = AudioDeviceManager()
        overlayWindow = OverlayWindow(appState: appState) { [weak self] in
            self?.cancelActiveOperation()
        }
        textInserter = TextInserter()
        modelManager = ModelManager(appState: appState)
        hotkeyManager = HotkeyManager(appState: appState) { [weak self] event, mode in
            Task { @MainActor in
                self?.handleHotkeyEvent(event, mode: mode)
            }
        }

        let initialUID = appState.selectedInputDeviceUID
        let initialDevice = initialUID.isEmpty ? nil : audioDeviceManager.device(forUID: initialUID)
        audioRecorder.setInputDevice(initialDevice)
    }

    private func setupBindings() {
        // Update menu bar icon based on state
        appState.$recordingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateStatusIcon(for: state)
                self?.updateMenu(for: state)
                self?.handleErrorAutoReset(for: state)
            }
            .store(in: &cancellables)

        // Update audio level
        audioRecorder.$currentLevel
            .receive(on: DispatchQueue.main)
            .assign(to: &appState.$audioLevel)

        appState.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.updateErrorMenuItem(message)
            }
            .store(in: &cancellables)

        appState.$transcriptionHistory
            .receive(on: DispatchQueue.main)
            .sink { [weak self] history in
                self?.rebuildRecentMenu(with: history)
            }
            .store(in: &cancellables)

        appState.$selectedInputDeviceUID
            .dropFirst()
            .sink { [weak self] uid in
                guard let self else { return }
                let device = uid.isEmpty ? nil : self.audioDeviceManager.device(forUID: uid)
                self.audioRecorder.setInputDevice(device)
                if self.appState.recordingState != .recording {
                    self.audioRecorder.resetAudioEngine()
                }
                if case .error = self.appState.recordingState {
                    self.appState.recordingState = .idle
                }
            }
            .store(in: &cancellables)

        audioDeviceManager.$inputDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                guard let self else { return }
                let selectedUID = self.appState.selectedInputDeviceUID
                guard !selectedUID.isEmpty else { return }
                if !devices.contains(where: { $0.uid == selectedUID }) {
                    self.appState.selectedInputDeviceUID = ""
                    self.audioRecorder.setInputDevice(nil)
                }
            }
            .store(in: &cancellables)

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
                    self?.updateEngineMenuItem()
                    self?.launchEngineInitialization()
                }
            }
            .store(in: &cancellables)

        appState.$whisperModel
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateEngineMenuItem()
                    self?.launchEngineInitialization()
                }
            }
            .store(in: &cancellables)

        appState.$parakeetModel
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateEngineMenuItem()
                    self?.launchEngineInitialization()
                }
            }
            .store(in: &cancellables)

        appState.$recordingDurationLimitEnabled
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshRecordingLimitTimer()
            }
            .store(in: &cancellables)

        appState.$recordingDurationLimitSeconds
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshRecordingLimitTimer()
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
            stopIconAnimation()
            button.image = MenuBarIcon.create()
        case .recording:
            startIconAnimation()
        case .transcribing:
            stopIconAnimation()
            button.image = MenuBarIcon.createTranscribing()
        case .error:
            stopIconAnimation()
            button.image = MenuBarIcon.createError()
        }
    }

    private func startIconAnimation(forLoading: Bool = false) {
        stopIconAnimation()
        iconAnimationFrame = 0
        isLoadingAnimation = forLoading

        // Update icon immediately
        if let button = statusItem.button {
            button.image = forLoading
                ? MenuBarIcon.createLoadingFrame(iconAnimationFrame)
                : MenuBarIcon.createRecordingFrame(iconAnimationFrame)
        }

        // Animate - slower for loading (pulse), faster for recording
        let interval: TimeInterval = forLoading ? 0.3 : 0.15
        iconAnimationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let button = self.statusItem.button else { return }
                self.iconAnimationFrame += 1
                button.image = self.isLoadingAnimation
                    ? MenuBarIcon.createLoadingFrame(self.iconAnimationFrame)
                    : MenuBarIcon.createRecordingFrame(self.iconAnimationFrame)
            }
        }
    }

    private func stopIconAnimation() {
        iconAnimationTimer?.invalidate()
        iconAnimationTimer = nil
        isLoadingAnimation = false
    }

    private func updateEngineMenuItem() {
        guard let item = engineMenuItem else { return }
        let label: String
        switch appState.transcriptionEngine {
        case .whisperKit:
            label = "WhisperKit · \(appState.whisperModel.rawValue)"
        case .parakeet:
            label = "Parakeet · \(appState.parakeetModel == .v2English ? "v2 English" : "v3 Multilingual")"
        case .openAI:
            label = "OpenAI · whisper-1"
        }
        item.title = "Engine: \(label)"
    }

    private func updateMenu(for state: RecordingState) {
        guard let recordingItem = recordingMenuItem else { return }

        switch state {
        case .idle:
            recordingItem.title = "Start Recording"
            recordingItem.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Record")
            recordingItem.isEnabled = true
        case .recording:
            recordingItem.title = "Stop Recording"
            recordingItem.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop")
            recordingItem.isEnabled = true
        case .transcribing:
            recordingItem.title = "Transcribing..."
            recordingItem.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Transcribing")
            recordingItem.isEnabled = false
        case .error:
            recordingItem.title = "Start Recording"
            recordingItem.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Record")
            recordingItem.isEnabled = true
        }
    }

    /// The error icon auto-returns to idle after a few seconds so the app
    /// never feels stuck; the "Last error" menu line keeps the detail.
    private func handleErrorAutoReset(for state: RecordingState) {
        errorResetTimer?.invalidate()
        errorResetTimer = nil

        guard case .error = state else { return }

        errorResetTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, case .error = self.appState.recordingState else { return }
                self.appState.recordingState = .idle
            }
        }
    }

    private func updateErrorMenuItem(_ message: String?) {
        guard let errorMenuItem, let errorSeparatorItem else { return }
        guard let message, !message.isEmpty else {
            errorMenuItem.isHidden = true
            errorSeparatorItem.isHidden = true
            return
        }

        let trimmed = message.count > 160 ? "\(message.prefix(157))..." : message
        // NSMenuItem never soft-wraps; only an attributedTitle with explicit
        // newlines renders multi-line, so wrap by hand to keep the menu narrow.
        let wrapped = Self.wordWrap("Last error: \(trimmed)", width: 48)
        errorMenuItem.attributedTitle = NSAttributedString(
            string: wrapped,
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        errorMenuItem.isHidden = false
        errorSeparatorItem.isHidden = false
    }

    private static func wordWrap(_ text: String, width: Int) -> String {
        var lines: [String] = []
        var current = ""

        for word in text.split(separator: " ") {
            if current.isEmpty {
                current = String(word)
            } else if current.count + 1 + word.count <= width {
                current += " \(word)"
            } else {
                lines.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { lines.append(current) }

        return lines.joined(separator: "\n")
    }

    private func updateInitializingState(_ isInitializing: Bool) {
        guard let menu = statusItem.menu,
              menu.items.count > 2 else { return }
        guard let recordingItem = recordingMenuItem else { return }

        if isInitializing {
            startIconAnimation(forLoading: true)
            // Recording stays available while the model loads — transcription
            // waits for initialization to finish.
            if appState.recordingState.isIdle {
                recordingItem.title = "Start Recording (model loading…)"
            }
        } else {
            stopIconAnimation()
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

    private func requestAccessibilityPermission() {
        // This will prompt the user if permission is not already granted
        // The system will show its own dialog asking for permission
        if !TextInserter.requestAccessibilityPermission() {
            // Permission not yet granted, the system dialog is now showing
            // We don't need to do anything else here - the user will grant
            // permission in System Settings
        }
    }

    private func showOnboardingIfNeeded() {
        guard !appState.hasCompletedOnboarding else {
            requestMicrophonePermission()
            requestAccessibilityPermission()
            return
        }

        if let window = onboardingWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let onboardingView = OnboardingView(
            openAppSettings: { [weak self] in
                self?.openSettings()
            },
            finishOnboarding: { [weak self] in
                self?.completeOnboarding()
            }
        )
        .environmentObject(appState)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Overwhisper"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()

        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func completeOnboarding() {
        appState.hasCompletedOnboarding = true
        onboardingWindow?.close()
        onboardingWindow = nil
        requestMicrophonePermission()
        requestAccessibilityPermission()
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
        // Prevent concurrent initialization - this check happens synchronously on @MainActor
        // before any suspension points, so it's race-free
        guard !appState.isInitializingEngine else {
            AppLogger.app.debug("Engine initialization already in progress, skipping")
            return
        }

        appState.isInitializingEngine = true
        defer { appState.isInitializingEngine = false }

        AppLogger.app.info("Starting engine initialization for: \(self.appState.transcriptionEngine.rawValue)")

        switch appState.transcriptionEngine {
        case .whisperKit:
            let engine = WhisperKitEngine(appState: appState, modelManager: modelManager)
            transcriptionEngine = engine  // Assign first so it's available
            await engine.initialize()
        case .parakeet:
            let engine = ParakeetEngine(appState: appState)
            transcriptionEngine = engine
            do {
                try await engine.initialize()
            } catch {
                AppLogger.app.error("Failed to initialize Parakeet engine: \(error.localizedDescription)")
                appState.lastError = "Failed to initialize Parakeet: \(error.localizedDescription)"
            }
        case .openAI:
            transcriptionEngine = OpenAIEngine(apiKey: appState.openAIAPIKey, translateToEnglish: appState.translateToEnglish, customVocabulary: appState.customVocabulary)
        }

        AppLogger.app.info("Engine initialization complete")
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
            switch event {
            case .keyDown:
                if appState.recordingState == .recording {
                    toggleKeyDownAt = nil
                    toggleKeyDownStartedRecording = false
                    stopAndTranscribe()
                } else if appState.recordingState.isIdle {
                    toggleKeyDownAt = Date()
                    toggleKeyDownStartedRecording = true
                    startRecording()
                }
            case .keyUp:
                // Held past the tap threshold → the user treated it as
                // push-to-talk, so release stops and transcribes.
                if toggleKeyDownStartedRecording,
                   appState.recordingState == .recording,
                   let downAt = toggleKeyDownAt,
                   Date().timeIntervalSince(downAt) >= Self.tapHoldThreshold {
                    stopAndTranscribe()
                }
                toggleKeyDownAt = nil
                toggleKeyDownStartedRecording = false
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

        // Recording is allowed while the engine is still loading — audio capture
        // doesn't need the model, and transcription waits for initialization.
        // Only block when transcription can never succeed (missing model/key).

        // Check if model is available when using WhisperKit
        if appState.transcriptionEngine == .whisperKit {
            let currentModel = appState.whisperModel.rawValue
            if !appState.downloadedModels.contains(currentModel) && !appState.isDownloadingModel {
                showNoModelAlert()
                return
            }
        }

        if appState.transcriptionEngine == .parakeet
            && !appState.parakeetDownloadedModels.contains(appState.parakeetModel.rawValue) {
            if !appState.isDownloadingModel {
                launchEngineInitialization()
            }
            showNotification(title: "Please Wait", body: "Parakeet model is still loading...")
            return
        }

        // Check if OpenAI API key is set when using OpenAI
        if appState.transcriptionEngine == .openAI && appState.openAIAPIKey.isEmpty {
            showNotification(title: "API Key Required", body: "Please set your OpenAI API key in Settings.")
            openSettings()
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
            startRecordingLimitTimer()
            overlayWindow.show(position: appState.overlayPosition)
        } catch {
            audioRecorder.resetAudioEngine()

            let deviceName = appState.selectedInputDeviceUID.isEmpty
                ? "System Default"
                : (audioDeviceManager.device(forUID: appState.selectedInputDeviceUID)?.name ?? "Selected Microphone")
            let nsError = error as NSError
            let errorDetails = "\(error.localizedDescription) (code \(nsError.code))"
            let message = "Couldn’t start recording with \(deviceName). \(errorDetails)"

            appState.recordingState = .error(message)
            appState.lastError = message
            if appState.showNotificationOnError {
                showNotification(title: "Recording Error", body: message)
            }
            showRecordingErrorAlert(message)
        }
    }

    private func showRecordingErrorAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Recording Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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

        stopRecordingLimitTimer()

        // Restore system audio if it was muted
        if appState.muteSystemAudioWhileRecording {
            SystemAudioManager.restoreSystemAudio()
        }

        let recordingDuration = appState.recordingDuration
        appState.stopRecordingTimer()
        appState.recordingState = .transcribing
        overlayWindow.showTranscribing()

        transcriptionTask = Task {
            let (engineLabel, modelLabel) = currentEngineLabels()
            let language = appState.language
            let started = Date()

            do {
                let url = try audioRecorder.stopRecording()
                let meanRMS = audioRecorder.meanRMS
                let peakRMS = audioRecorder.peakRMS

                if appState.skipSilentRecordings && Self.isBelowSilenceThreshold(meanRMS: meanRMS) {
                    let meanDb = AppDelegate.dbFromRMS(meanRMS)
                    let peakDb = AppDelegate.dbFromRMS(peakRMS)
                    AppLogger.audio.info(
                        "Skipping silent recording — mean RMS \(meanRMS) (\(meanDb) dBFS, peak \(peakDb) dBFS) below threshold \(AppDelegate.silenceThresholdDb) dBFS"
                    )

                    let latency = Date().timeIntervalSince(started)
                    finalizeAudioFile(
                        url: url,
                        engine: engineLabel,
                        model: modelLabel,
                        recordingDuration: recordingDuration,
                        transcribedText: "",
                        latency: latency,
                        language: language,
                        errorMessage: String(format: "No speech detected (mean %.1f dBFS, peak %.1f dBFS)", meanDb, peakDb),
                        usedCloudFallback: false
                    )

                    appState.recordingState = .idle
                    overlayWindow.hide()
                    return
                }

                await transcribeAndDeliver(audioURL: url, recordingDuration: recordingDuration)

            } catch {
                let latency = Date().timeIntervalSince(started)
                AppLogger.transcription.error("Failed to stop recording: \(error.localizedDescription)")

                finalizeAudioFile(
                    url: nil,
                    engine: engineLabel,
                    model: modelLabel,
                    recordingDuration: recordingDuration,
                    transcribedText: "",
                    latency: latency,
                    language: language,
                    errorMessage: error.localizedDescription,
                    usedCloudFallback: false
                )
                appState.recordingState = .error(error.localizedDescription)
                appState.lastError = error.localizedDescription
                if appState.showNotificationOnError {
                    showNotification(title: "Transcription Error", body: error.localizedDescription)
                }
                overlayWindow.hide()
            }
        }
    }

    private func currentEngineLabels() -> (engine: String, model: String) {
        let engineType = appState.transcriptionEngine
        let modelLabel: String
        switch engineType {
        case .whisperKit:
            modelLabel = "WhisperKit \(appState.whisperModel.rawValue)"
        case .parakeet:
            modelLabel = appState.parakeetModel.displayName
        case .openAI:
            modelLabel = "OpenAI whisper-1"
        }
        return (engineType.rawValue, modelLabel)
    }

    /// Transcribes an audio file and delivers the result (history + paste).
    /// Shared by the normal recording flow and "Retry Last Transcription".
    /// Expects recordingState == .transcribing and the overlay already showing.
    private func transcribeAndDeliver(audioURL: URL, recordingDuration: TimeInterval) async {
        let engineType = appState.transcriptionEngine
        let (engineLabel, modelLabel) = currentEngineLabels()
        let language = appState.language
        let started = Date()

        // Recording may have started while the engine was still loading —
        // wait for any in-flight initialization before transcribing.
        await initializationTask?.value
        while appState.isInitializingEngine && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        if Task.isCancelled {
            recordCancelledTranscription(
                audioURL: audioURL, engine: engineLabel, model: modelLabel,
                recordingDuration: recordingDuration, latency: Date().timeIntervalSince(started), language: language
            )
            return
        }

        do {
            guard let engine = transcriptionEngine else {
                throw TranscriptionError.engineNotInitialized
            }

            let text = try await engine.transcribe(audioURL: audioURL)
            let latency = Date().timeIntervalSince(started)

            // Cancelled mid-transcription — discard the result, but keep the
            // audio in the debug store so "Retry Last Transcription" can
            // resurrect a mistaken cancel.
            if Task.isCancelled {
                recordCancelledTranscription(
                    audioURL: audioURL, engine: engineLabel, model: modelLabel,
                    recordingDuration: recordingDuration, latency: latency, language: language
                )
                return
            }

            let cleaned = AppDelegate.stripNonSpeechAnnotations(text)
            let finalText = cleaned.isEmpty ? "" : appState.applyTextReplacements(cleaned)

            finalizeAudioFile(
                url: audioURL,
                engine: engineLabel,
                model: modelLabel,
                recordingDuration: recordingDuration,
                transcribedText: finalText,
                latency: latency,
                language: language,
                errorMessage: nil,
                usedCloudFallback: false
            )

            deliverTranscription(finalText)

            appState.recordingState = .idle
            overlayWindow.hide()

        } catch {
            let latency = Date().timeIntervalSince(started)

            if Task.isCancelled || error is CancellationError {
                recordCancelledTranscription(
                    audioURL: audioURL, engine: engineLabel, model: modelLabel,
                    recordingDuration: recordingDuration, latency: latency, language: language
                )
                return
            }

            AppLogger.transcription.error("Transcription error: \(error.localizedDescription)")

            // Try cloud fallback if enabled
            let shouldTryFallback = appState.enableCloudFallback
                && engineType == .whisperKit
                && !appState.openAIAPIKey.isEmpty

            if shouldTryFallback {
                let fallbackSucceeded = await tryCloudFallback(
                    audioURL: audioURL,
                    recordingDuration: recordingDuration,
                    language: language,
                    initialError: error.localizedDescription
                )
                if !fallbackSucceeded {
                    appState.recordingState = .error(error.localizedDescription)
                    appState.lastError = error.localizedDescription
                    if appState.showNotificationOnError {
                        showNotification(title: "Transcription Error", body: "Local and cloud transcription both failed")
                    }
                }
            } else {
                let session = finalizeAudioFile(
                    url: audioURL,
                    engine: engineLabel,
                    model: modelLabel,
                    recordingDuration: recordingDuration,
                    transcribedText: "",
                    latency: latency,
                    language: language,
                    errorMessage: error.localizedDescription,
                    usedCloudFallback: false
                )
                rememberFailedSession(session)
                appState.recordingState = .error(error.localizedDescription)
                appState.lastError = error.localizedDescription
                if appState.showNotificationOnError {
                    showNotification(title: "Transcription Error", body: error.localizedDescription)
                }
            }

            overlayWindow.hide()
        }
    }

    private func deliverTranscription(_ text: String) {
        guard !text.isEmpty else { return }

        appState.addTranscriptionHistory(text)
        let didPaste = textInserter.insertText(text)

        if didPaste {
            if appState.playSoundOnCompletion {
                NSSound(named: .init("Tink"))?.play()
            }
        } else {
            // Accessibility permission not granted - text is in clipboard
            showNotification(
                title: "Text Copied",
                body: "Accessibility permission needed for auto-paste. Text copied to clipboard - press Cmd+V to paste."
            )
        }
    }

    private func recordCancelledTranscription(
        audioURL: URL,
        engine: String,
        model: String,
        recordingDuration: TimeInterval,
        latency: TimeInterval,
        language: String
    ) {
        let session = finalizeAudioFile(
            url: audioURL,
            engine: engine,
            model: model,
            recordingDuration: recordingDuration,
            transcribedText: "",
            latency: latency,
            language: language,
            errorMessage: "Cancelled by user",
            usedCloudFallback: false
        )
        rememberFailedSession(session)
    }

    // MARK: - Retry last failed transcription

    private func rememberFailedSession(_ session: TranscriptionDebugSession) {
        // Retry only works while the audio survives in the debug store
        guard session.audioFileName != nil else { return }
        lastFailedSession = session
        retryMenuItem?.isHidden = false
    }

    private func clearFailedSession() {
        lastFailedSession = nil
        retryMenuItem?.isHidden = true
    }

    @objc private func retryLastTranscription() {
        guard appState.recordingState.isIdle else { return }

        guard let session = lastFailedSession,
              let audioURL = appState.debugSessionStore.audioURL(for: session) else {
            clearFailedSession()
            showNotification(title: "Retry Unavailable", body: "The audio from the failed transcription is no longer available.")
            return
        }

        clearFailedSession()
        appState.recordingState = .transcribing
        overlayWindow.showTranscribing()

        transcriptionTask = Task {
            await transcribeAndDeliver(audioURL: audioURL, recordingDuration: session.recordingDurationSeconds)
        }
    }

    private func tryCloudFallback(
        audioURL: URL,
        recordingDuration: TimeInterval,
        language: String,
        initialError: String
    ) async -> Bool {
        showNotification(title: "Fallback", body: "Local transcription failed, trying cloud...")

        let started = Date()
        let openAIEngine = OpenAIEngine(apiKey: appState.openAIAPIKey, translateToEnglish: appState.translateToEnglish, customVocabulary: appState.customVocabulary)

        do {
            let text = try await openAIEngine.transcribe(audioURL: audioURL)
            let latency = Date().timeIntervalSince(started)

            let cleaned = AppDelegate.stripNonSpeechAnnotations(text)
            let finalText = cleaned.isEmpty ? "" : appState.applyTextReplacements(cleaned)

            finalizeAudioFile(
                url: audioURL,
                engine: "OpenAI API (fallback)",
                model: "OpenAI whisper-1",
                recordingDuration: recordingDuration,
                transcribedText: finalText,
                latency: latency,
                language: language,
                errorMessage: nil,
                usedCloudFallback: true
            )

            deliverTranscription(finalText)

            appState.recordingState = .idle
            return true

        } catch {
            let latency = Date().timeIntervalSince(started)
            AppLogger.transcription.error("Cloud fallback error: \(error.localizedDescription)")

            let session = finalizeAudioFile(
                url: audioURL,
                engine: "OpenAI API (fallback)",
                model: "OpenAI whisper-1",
                recordingDuration: recordingDuration,
                transcribedText: "",
                latency: latency,
                language: language,
                errorMessage: "Local: \(initialError) — Cloud: \(error.localizedDescription)",
                usedCloudFallback: true
            )
            rememberFailedSession(session)

            return false
        }
    }

    @discardableResult
    private func finalizeAudioFile(
        url: URL?,
        engine: String,
        model: String,
        recordingDuration: TimeInterval,
        transcribedText: String,
        latency: TimeInterval,
        language: String,
        errorMessage: String?,
        usedCloudFallback: Bool
    ) -> TranscriptionDebugSession {
        appState.debugSessionStore.record(
            engine: engine,
            model: model,
            sourceAudioURL: url,
            recordingDuration: recordingDuration,
            transcribedText: transcribedText,
            latencySeconds: latency,
            language: language.isEmpty || language == "auto" ? nil : language,
            errorMessage: errorMessage,
            usedCloudFallback: usedCloudFallback
        )
    }

    private func cancelRecording() {
        guard appState.recordingState == .recording else { return }

        stopRecordingLimitTimer()

        // Restore system audio if it was muted
        if appState.muteSystemAudioWhileRecording {
            SystemAudioManager.restoreSystemAudio()
        }

        appState.stopRecordingTimer()
        audioRecorder.cancelRecording()
        appState.recordingState = .idle
        overlayWindow.hide()
    }

    private func setupEscapeKeyMonitor() {
        escapeKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                Task { @MainActor in
                    self?.cancelActiveOperation()
                }
            }
        }
    }

    private func cancelActiveOperation() {
        switch appState.recordingState {
        case .recording:
            cancelRecording()
        case .transcribing:
            cancelTranscription()
        case .idle, .error:
            break
        }
    }

    private func cancelTranscription() {
        guard appState.recordingState == .transcribing else { return }

        transcriptionTask?.cancel()
        appState.recordingState = .idle
        overlayWindow.hide()
    }

    private func startRecordingLimitTimer() {
        stopRecordingLimitTimer()

        guard appState.recordingDurationLimitEnabled else { return }
        let limit = max(10, appState.recordingDurationLimitSeconds)

        recordingLimitTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(limit), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.appState.recordingState == .recording {
                    self.stopAndTranscribe()
                }
            }
        }
    }

    private func stopRecordingLimitTimer() {
        recordingLimitTimer?.invalidate()
        recordingLimitTimer = nil
    }

    private func refreshRecordingLimitTimer() {
        if appState.recordingState == .recording {
            startRecordingLimitTimer()
        } else {
            stopRecordingLimitTimer()
        }
    }

    private func showNotification(title: String, body: String) {
        // UNUserNotificationCenter requires a proper app bundle
        // When running via swift run, we don't have one, so use a fallback
        guard Bundle.main.bundleIdentifier != nil else {
            // Fallback: just print to console when running without bundle
            AppLogger.app.info("[\(title)] \(body)")
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
            .environmentObject(audioDeviceManager)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Overwhisper Settings"
        window.minSize = NSSize(width: 500, height: 450)
        window.contentView = NSHostingView(rootView: settingsView)
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace]
        let frameName = "OverwhisperSettingsWindow"
        window.setFrameAutosaveName(frameName)
        if !window.setFrameUsingName(frameName) {
            window.center()
        }
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

    // MARK: - Silence detection

    /// Mean RMS amplitude (dBFS) below which a recording is considered silent and
    /// is skipped before sending to the transcription engine. Whisper hallucinates
    /// "you" / "Thanks for watching." on near-silent inputs, so gating here keeps
    /// noise out of the user's text. Threshold tuned against typical speech levels
    /// (-25 to -35 dBFS mean) and condenser-mic noise floor (-45 dBFS or lower).
    static let silenceThresholdDb: Float = -38.0

    static func isBelowSilenceThreshold(meanRMS: Float) -> Bool {
        // Treat exactly-zero buffers (e.g. failed converter chains) as silent too.
        guard meanRMS > 0 else { return true }
        return dbFromRMS(meanRMS) < silenceThresholdDb
    }

    static func dbFromRMS(_ rms: Float) -> Float {
        20 * log10(max(rms, 1e-9))
    }

    // MARK: - Non-speech annotation stripping

    /// Strips Whisper-style non-speech annotations from a transcription:
    /// `*cough*`, `[Music]`, `[Applause]`, `[BLANK_AUDIO]`, `(coughs)`, etc.
    /// Returns the cleaned text trimmed of surrounding whitespace.
    static func stripNonSpeechAnnotations(_ text: String) -> String {
        var result = text

        // Asterisk-wrapped: *cough*, *sigh*, *laughs*
        result = result.replacingOccurrences(
            of: #"\*[^*\n]{1,60}\*"#,
            with: "",
            options: .regularExpression
        )

        // Bracket-wrapped: [Music], [Applause], [BLANK_AUDIO], [silence]
        result = result.replacingOccurrences(
            of: #"\[[^\]\n]{1,60}\]"#,
            with: "",
            options: .regularExpression
        )

        // Parenthetical sound effects — only match a curated list so we don't
        // strip legitimate parentheticals like "(see fig. 2)".
        let parentheticalPattern = #"(?i)\((?:cough(?:s|ing|ed)?|sigh(?:s|ing|ed)?|laugh(?:s|ing|ed|ter)?|sneeze(?:s|d)?|breath(?:e|es|ing|ed)?|gasp(?:s|ing|ed)?|music|applause|silence|noise|static|mumbl(?:e|es|ing)|whisper(?:s|ing)?|cry(?:ing|ies|ied)?|chuckl(?:e|es|ing)|groan(?:s|ing|ed)?|grunt(?:s|ing|ed)?|hum(?:s|ming|med)?|shout(?:s|ing|ed)?|yell(?:s|ing|ed)?|background(?:\s+\w+){0,3}|inaudible|indistinct(?:\s+\w+){0,3})\)"#
        result = result.replacingOccurrences(
            of: parentheticalPattern,
            with: "",
            options: .regularExpression
        )

        // Collapse leftover double-spaces and stray punctuation islands like " . "
        result = result.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"^\s*[.,;:!?]+\s*"#,
            with: "",
            options: .regularExpression
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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
