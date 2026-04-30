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
    private var audioDeviceManager: AudioDeviceManager!
    private var overlayWindow: OverlayWindow!
    private var textInserter: TextInserter!
    private var transcriptionEngine: (any TranscriptionEngine)?
    private var modelManager: ModelManager!
    private var settingsWindow: NSWindow?
    private var recordingMenuItem: NSMenuItem?
    private var errorSeparatorItem: NSMenuItem?
    private var errorMenuItem: NSMenuItem?
    private var onboardingWindow: NSWindow?
    private var recordingLimitTimer: Timer?

    private var cancellables = Set<AnyCancellable>()
    private var initializationTask: Task<Void, Never>?
    private var escapeKeyMonitor: Any?
    private var iconAnimationTimer: Timer?
    private var iconAnimationFrame: Int = 0
    private var isLoadingAnimation: Bool = false

    override init() {
        // Initialize Sparkle updater
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
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

        showOnboardingIfNeeded()

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
            button.image = MenuBarIcon.create()
        }

        let menu = NSMenu()

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let versionItem = NSMenuItem(title: "Overwhisper v\(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let builtByItem = NSMenuItem(title: "Built by Hal Shin", action: nil, keyEquivalent: "")
        builtByItem.isEnabled = false
        menu.addItem(builtByItem)

        menu.addItem(NSMenuItem.separator())

        let recordingItem = NSMenuItem(title: "Start Recording", action: #selector(toggleRecording), keyEquivalent: "")
        recordingItem.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Record")
        menu.addItem(recordingItem)
        self.recordingMenuItem = recordingItem

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

        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.image = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: "Update")
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Overwhisper", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func setupComponents() {
        audioRecorder = AudioRecorder()
        audioDeviceManager = AudioDeviceManager()
        overlayWindow = OverlayWindow(appState: appState)
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

    private func updateErrorMenuItem(_ message: String?) {
        guard let errorMenuItem, let errorSeparatorItem else { return }
        guard let message, !message.isEmpty else {
            errorMenuItem.isHidden = true
            errorSeparatorItem.isHidden = true
            return
        }

        let trimmed = message.count > 160 ? "\(message.prefix(157))..." : message
        errorMenuItem.title = "Last error: \(trimmed)"
        errorMenuItem.isHidden = false
        errorSeparatorItem.isHidden = false
    }

    private func updateInitializingState(_ isInitializing: Bool) {
        guard let menu = statusItem.menu,
              menu.items.count > 2 else { return }
        guard let recordingItem = recordingMenuItem else { return }

        if isInitializing {
            startIconAnimation(forLoading: true)
            recordingItem.title = "Loading Model..."
            recordingItem.isEnabled = false
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
            appState.addDebugLog("Accessibility permission requested", source: "Permissions")
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
            startRecordingLimitTimer()
            overlayWindow.show(position: appState.overlayPosition)
            startEscapeKeyMonitor()
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

        stopEscapeKeyMonitor()
        stopRecordingLimitTimer()

        // Restore system audio if it was muted
        if appState.muteSystemAudioWhileRecording {
            SystemAudioManager.restoreSystemAudio()
        }

        let recordingDuration = appState.recordingDuration
        appState.stopRecordingTimer()
        appState.recordingState = .transcribing
        overlayWindow.showTranscribing()

        Task {
            var audioURL: URL?
            let engineType = appState.transcriptionEngine
            let engineLabel = engineType.rawValue
            let modelLabel = engineType == .openAI
                ? "OpenAI whisper-1"
                : "WhisperKit \(appState.whisperModel.rawValue)"
            let language = appState.language
            let started = Date()

            do {
                audioURL = try audioRecorder.stopRecording()
                let meanRMS = audioRecorder.meanRMS
                let peakRMS = audioRecorder.peakRMS

                guard let url = audioURL else {
                    throw TranscriptionError.noAudioData
                }

                if appState.skipSilentRecordings && Self.isBelowSilenceThreshold(meanRMS: meanRMS) {
                    let meanDb = AppDelegate.dbFromRMS(meanRMS)
                    let peakDb = AppDelegate.dbFromRMS(peakRMS)
                    AppLogger.audio.info(
                        "Skipping silent recording — mean RMS \(meanRMS) (\(meanDb) dBFS, peak \(peakDb) dBFS) below threshold \(AppDelegate.silenceThresholdDb) dBFS"
                    )
                    appState.addDebugLog(
                        String(format: "Skipped silent recording (mean %.1f dBFS, peak %.1f dBFS)", meanDb, peakDb),
                        source: "Transcription"
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

                guard let engine = transcriptionEngine else {
                    throw TranscriptionError.engineNotInitialized
                }

                appState.addDebugLog("Starting transcription with \(modelLabel)", source: "Transcription")

                let text = try await engine.transcribe(audioURL: url)
                let latency = Date().timeIntervalSince(started)

                let cleaned = AppDelegate.stripNonSpeechAnnotations(text)
                if !text.isEmpty && cleaned.isEmpty {
                    appState.addDebugLog(
                        "Skipped non-speech annotation: \(text)", source: "Transcription")
                }
                let finalText = cleaned.isEmpty ? "" : appState.applyTextReplacements(cleaned)

                finalizeAudioFile(
                    url: url,
                    engine: engineLabel,
                    model: modelLabel,
                    recordingDuration: recordingDuration,
                    transcribedText: finalText,
                    latency: latency,
                    language: language,
                    errorMessage: nil,
                    usedCloudFallback: false
                )

                if !finalText.isEmpty {
                    appState.addTranscriptionHistory(finalText)
                    let didPaste = textInserter.insertText(finalText)

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

                appState.recordingState = .idle
                overlayWindow.hide()

            } catch {
                let latency = Date().timeIntervalSince(started)
                AppLogger.transcription.error("Transcription error: \(error.localizedDescription)")
                appState.addDebugLog("Transcription failed: \(error.localizedDescription)", source: "Transcription")

                // Try cloud fallback if enabled and we have the audio file
                let shouldTryFallback = appState.enableCloudFallback
                    && engineType == .whisperKit
                    && !appState.openAIAPIKey.isEmpty
                    && audioURL != nil

                if shouldTryFallback, let url = audioURL {
                    // Record the local failure (without consuming the audio file)
                    recordSessionMetadata(
                        engine: engineLabel,
                        model: modelLabel,
                        recordingDuration: recordingDuration,
                        transcribedText: "",
                        latency: latency,
                        language: language,
                        errorMessage: error.localizedDescription,
                        usedCloudFallback: false
                    )

                    let fallbackSucceeded = await tryCloudFallback(
                        audioURL: url,
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
                    finalizeAudioFile(
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
                    appState.recordingState = .error(error.localizedDescription)
                    appState.lastError = error.localizedDescription
                    if appState.showNotificationOnError {
                        showNotification(title: "Transcription Error", body: error.localizedDescription)
                    }
                }

                overlayWindow.hide()
            }
        }
    }

    private func tryCloudFallback(
        audioURL: URL,
        recordingDuration: TimeInterval,
        language: String,
        initialError: String
    ) async -> Bool {
        appState.addDebugLog("Attempting cloud fallback with OpenAI", source: "Transcription")
        showNotification(title: "Fallback", body: "Local transcription failed, trying cloud...")

        let started = Date()
        let openAIEngine = OpenAIEngine(apiKey: appState.openAIAPIKey, translateToEnglish: appState.translateToEnglish, customVocabulary: appState.customVocabulary)

        do {
            let text = try await openAIEngine.transcribe(audioURL: audioURL)
            let latency = Date().timeIntervalSince(started)

            let cleaned = AppDelegate.stripNonSpeechAnnotations(text)
            if !text.isEmpty && cleaned.isEmpty {
                appState.addDebugLog(
                    "Skipped non-speech annotation (fallback): \(text)", source: "Transcription")
            }
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

            if !finalText.isEmpty {
                appState.addTranscriptionHistory(finalText)
                let didPaste = textInserter.insertText(finalText)
                appState.addDebugLog("Cloud fallback succeeded", source: "Transcription")

                if didPaste {
                    if appState.playSoundOnCompletion {
                        NSSound(named: .init("Tink"))?.play()
                    }
                } else {
                    showNotification(
                        title: "Text Copied",
                        body: "Accessibility permission needed for auto-paste. Text copied to clipboard - press Cmd+V to paste."
                    )
                }
            }

            appState.recordingState = .idle
            return true

        } catch {
            let latency = Date().timeIntervalSince(started)
            AppLogger.transcription.error("Cloud fallback error: \(error.localizedDescription)")
            appState.addDebugLog("Cloud fallback failed: \(error.localizedDescription)", source: "Transcription")

            finalizeAudioFile(
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

            return false
        }
    }

    /// Persists session metadata (and the audio file when debug mode is on) and
    /// removes the temporary audio file when it isn't needed.
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
    ) {
        if appState.debugModeEnabled {
            _ = appState.debugSessionStore.record(
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
        } else if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Records a metadata-only session entry without touching the audio file.
    /// Used to log a local failure before retrying via cloud fallback.
    private func recordSessionMetadata(
        engine: String,
        model: String,
        recordingDuration: TimeInterval,
        transcribedText: String,
        latency: TimeInterval,
        language: String,
        errorMessage: String?,
        usedCloudFallback: Bool
    ) {
        guard appState.debugModeEnabled else { return }
        _ = appState.debugSessionStore.record(
            engine: engine,
            model: model,
            sourceAudioURL: nil,
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

        stopEscapeKeyMonitor()
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
