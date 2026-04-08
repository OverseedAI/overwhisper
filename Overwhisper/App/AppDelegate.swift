import AVFoundation
import AppKit
import Combine
import Sparkle
import SwiftUI
import UserNotifications

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
    updaterController = SPUStandardUpdaterController(
      startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
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

    let recordingItem = NSMenuItem(
      title: "Start Recording", action: #selector(toggleRecording), keyEquivalent: "")
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

    let updateItem = NSMenuItem(
      title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
    updateItem.image = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: "Update")
    menu.addItem(updateItem)

    menu.addItem(
      NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      NSMenuItem(title: "Quit Overwhisper", action: #selector(quitApp), keyEquivalent: "q"))

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

    appState.$parakeetModel
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
      button.image =
        forLoading
        ? MenuBarIcon.createLoadingFrame(iconAnimationFrame)
        : MenuBarIcon.createRecordingFrame(iconAnimationFrame)
    }

    // Animate - slower for loading (pulse), faster for recording
    let interval: TimeInterval = forLoading ? 0.3 : 0.15
    iconAnimationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
      [weak self] _ in
      Task { @MainActor in
        guard let self, let button = self.statusItem.button else { return }
        self.iconAnimationFrame += 1
        button.image =
          self.isLoadingAnimation
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
      recordingItem.image = NSImage(
        systemSymbolName: "mic.fill", accessibilityDescription: "Record")
      recordingItem.isEnabled = true
    case .recording:
      recordingItem.title = "Stop Recording"
      recordingItem.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop")
      recordingItem.isEnabled = true
    case .transcribing:
      recordingItem.title = "Transcribing..."
      recordingItem.image = NSImage(
        systemSymbolName: "ellipsis.circle", accessibilityDescription: "Transcribing")
      recordingItem.isEnabled = false
    case .error:
      recordingItem.title = "Start Recording"
      recordingItem.image = NSImage(
        systemSymbolName: "mic.fill", accessibilityDescription: "Record")
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
      menu.items.count > 2
    else { return }
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
    alert.informativeText =
      "Overwhisper needs \(permission.lowercased()) access to function. Please enable it in System Settings > Privacy & Security > \(permission)."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Cancel")

    if alert.runModal() == .alertFirstButtonReturn {
      if let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(permission)")
      {
        NSWorkspace.shared.open(url)
      }
    }
  }

  private func initializeTranscriptionEngine() async {
    // Prevent concurrent initialization
    guard !appState.isInitializingEngine else {
      AppLogger.app.debug("Engine initialization already in progress, skipping")
      return
    }

    let engineType = appState.transcriptionEngine
    let modelType = appState.parakeetModel

    AppLogger.app.info(
      "Starting engine initialization for: \(engineType.rawValue), model: \(modelType.displayName)")

    appState.isInitializingEngine = true
    appState.isDownloadingModel = true
    appState.isModelDownloaded = false

    defer {
      Task { @MainActor in
        self.appState.isInitializingEngine = false
      }
    }

    switch engineType {
    case .whisperKit:
      let engine = WhisperKitEngine(appState: appState, modelManager: modelManager)
      transcriptionEngine = engine
      await engine.initialize()
    case .parakeet:
      let engine = ParakeetEngine(appState: appState)
      transcriptionEngine = engine
      await engine.initialize()
    case .openAI:
      transcriptionEngine = OpenAIEngine(
        apiKey: appState.openAIAPIKey, translateToEnglish: appState.translateToEnglish,
        customVocabulary: appState.customVocabulary)
      await MainActor.run {
        self.appState.isDownloadingModel = false
        self.appState.isModelDownloaded = true
      }
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

    // If engine needs initialization, trigger it and wait briefly
    if appState.isInitializingEngine || appState.isDownloadingModel || transcriptionEngine == nil {
      Task {
        if transcriptionEngine == nil {
          await initializeTranscriptionEngine()
        }
        // Wait a bit and try again
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        if self.appState.recordingState.isIdle {
          await MainActor.run {
            self.startRecording()
          }
        }
      }
      return
    }

    // Check if model is available when using WhisperKit
    if appState.transcriptionEngine == .whisperKit {
      let currentModel = appState.whisperModel.rawValue
      if !appState.downloadedModels.contains(currentModel) {
        showNoModelAlert()
        return
      }
    }

    // Check if model is available when using Parakeet
    if appState.transcriptionEngine == .parakeet {
      if !appState.isModelDownloaded {
        // Trigger initialization and wait
        Task {
          await initializeTranscriptionEngine()
          // Wait for initialization to complete
          while self.appState.isInitializingEngine || self.appState.isDownloadingModel {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
          }
          if self.appState.recordingState.isIdle && self.appState.isModelDownloaded {
            await MainActor.run {
              self.startRecording()
            }
          }
        }
        return
      }
    }

    // Check if OpenAI API key is set when using OpenAI
    if appState.transcriptionEngine == .openAI && appState.openAIAPIKey.isEmpty {
      showNotification(
        title: "API Key Required", body: "Please set your OpenAI API key in Settings.")
      openSettings()
      return
    }

    // Ensure we have an engine
    guard transcriptionEngine != nil else {
      showNotification(
        title: "Engine Not Ready",
        body: "Transcription engine is not initialized. Please wait or check settings.")
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

      let deviceName =
        appState.selectedInputDeviceUID.isEmpty
        ? "System Default"
        : (audioDeviceManager.device(forUID: appState.selectedInputDeviceUID)?.name
          ?? "Selected Microphone")
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
    alert.informativeText =
      "You need to download a transcription model before recording. Would you like to open Settings to download one?"
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

    appState.stopRecordingTimer()
    appState.recordingState = .transcribing
    overlayWindow.showTranscribing()

    Task {
      var audioURL: URL?

      do {
        audioURL = try audioRecorder.stopRecording()

        guard let url = audioURL else {
          throw TranscriptionError.noAudioData
        }

        guard let engine = transcriptionEngine else {
          throw TranscriptionError.engineNotInitialized
        }

        // Log which model is being used
        let modelInfo: String
        switch appState.transcriptionEngine {
        case .whisperKit:
          modelInfo = "WhisperKit \(appState.whisperModel.rawValue)"
        case .parakeet:
          modelInfo = appState.parakeetModel.displayName
        case .openAI:
          modelInfo = "OpenAI whisper-1"
        }
        appState.addDebugLog("Starting transcription with \(modelInfo)", source: "Transcription")

        let text = try await engine.transcribe(audioURL: url)

        // Clean up audio file after successful transcription
        try? FileManager.default.removeItem(at: url)

        if !text.isEmpty {
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
              body:
                "Accessibility permission needed for auto-paste. Text copied to clipboard - press Cmd+V to paste."
            )
          }
        }

        appState.recordingState = .idle
        overlayWindow.hide()

      } catch {
        AppLogger.transcription.error("Transcription error: \(error.localizedDescription)")
        appState.addDebugLog(
          "Transcription failed: \(error.localizedDescription)", source: "Transcription")

        // Try cloud fallback if enabled and we have the audio file
        let shouldTryFallback =
          appState.enableCloudFallback
          && appState.transcriptionEngine == .whisperKit
          && !appState.openAIAPIKey.isEmpty
          && audioURL != nil

        if shouldTryFallback, let url = audioURL {
          let fallbackSucceeded = await tryCloudFallback(audioURL: url)
          if !fallbackSucceeded {
            appState.recordingState = .error(error.localizedDescription)
            appState.lastError = error.localizedDescription
            if appState.showNotificationOnError {
              showNotification(
                title: "Transcription Error", body: "Local and cloud transcription both failed")
            }
          }
        } else {
          // Clean up audio file if no fallback attempted
          if let url = audioURL {
            try? FileManager.default.removeItem(at: url)
          }
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

  private func tryCloudFallback(audioURL: URL) async -> Bool {
    appState.addDebugLog("Attempting cloud fallback with OpenAI", source: "Transcription")
    showNotification(title: "Fallback", body: "Local transcription failed, trying cloud...")

    let openAIEngine = OpenAIEngine(
      apiKey: appState.openAIAPIKey, translateToEnglish: appState.translateToEnglish,
      customVocabulary: appState.customVocabulary)

    do {
      let text = try await openAIEngine.transcribe(audioURL: audioURL)

      // Clean up audio file after successful fallback
      try? FileManager.default.removeItem(at: audioURL)

      if !text.isEmpty {
        appState.addTranscriptionHistory(text)
        let didPaste = textInserter.insertText(text)
        appState.addDebugLog("Cloud fallback succeeded", source: "Transcription")

        if didPaste {
          if appState.playSoundOnCompletion {
            NSSound(named: .init("Tink"))?.play()
          }
        } else {
          showNotification(
            title: "Text Copied",
            body:
              "Accessibility permission needed for auto-paste. Text copied to clipboard - press Cmd+V to paste."
          )
        }
      }

      appState.recordingState = .idle
      return true

    } catch {
      AppLogger.transcription.error("Cloud fallback error: \(error.localizedDescription)")
      appState.addDebugLog(
        "Cloud fallback failed: \(error.localizedDescription)", source: "Transcription")

      // Clean up audio file after failed fallback
      try? FileManager.default.removeItem(at: audioURL)

      return false
    }
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
      if event.keyCode == 53 {  // Escape key
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

    recordingLimitTimer = Timer.scheduledTimer(
      withTimeInterval: TimeInterval(limit), repeats: false
    ) { [weak self] _ in
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
