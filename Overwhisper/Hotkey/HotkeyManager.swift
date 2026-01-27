import AppKit
import Carbon.HIToolbox
import HotKey

enum HotkeyEvent {
    case keyDown
    case keyUp
}

enum HotkeyMode {
    case toggle
    case pushToTalk
}

@MainActor
class HotkeyManager {
    private var toggleHotKey: HotKey?
    private var pushToTalkHotKey: HotKey?
    private let appState: AppState
    private let eventHandler: (HotkeyEvent, HotkeyMode) -> Void

    // Track key state for push-to-talk
    private var isPushToTalkKeyDown = false

    init(appState: AppState, eventHandler: @escaping (HotkeyEvent, HotkeyMode) -> Void) {
        self.appState = appState
        self.eventHandler = eventHandler

        registerHotkeys()
        _ = checkAccessibilityPermission()
    }

    func registerHotkeys() {
        registerToggleHotkey(config: appState.toggleHotkeyConfig)
        registerPushToTalkHotkey(config: appState.pushToTalkHotkeyConfig)
    }

    func registerToggleHotkey(config: HotkeyConfig) {
        toggleHotKey = nil

        // Skip registration if hotkey is not set
        guard !config.isEmpty else {
            AppLogger.hotkey.debug("Toggle hotkey not set, skipping registration")
            return
        }

        guard let key = Key(carbonKeyCode: UInt32(config.keyCode)) else {
            AppLogger.hotkey.error("Invalid toggle key code: \(config.keyCode)")
            return
        }

        let modifiers = convertModifiers(config.modifiers)
        toggleHotKey = HotKey(key: key, modifiers: modifiers)

        toggleHotKey?.keyDownHandler = { [weak self] in
            self?.eventHandler(.keyDown, .toggle)
        }
        // Toggle mode doesn't need keyUp
    }

    func registerPushToTalkHotkey(config: HotkeyConfig) {
        pushToTalkHotKey = nil

        // Skip registration if hotkey is not set
        guard !config.isEmpty else {
            AppLogger.hotkey.debug("Push-to-talk hotkey not set, skipping registration")
            return
        }

        guard let key = Key(carbonKeyCode: UInt32(config.keyCode)) else {
            AppLogger.hotkey.error("Invalid push-to-talk key code: \(config.keyCode)")
            return
        }

        let modifiers = convertModifiers(config.modifiers)
        pushToTalkHotKey = HotKey(key: key, modifiers: modifiers)

        pushToTalkHotKey?.keyDownHandler = { [weak self] in
            guard let self = self else { return }
            self.isPushToTalkKeyDown = true
            self.eventHandler(.keyDown, .pushToTalk)
        }

        pushToTalkHotKey?.keyUpHandler = { [weak self] in
            guard let self = self else { return }
            if self.isPushToTalkKeyDown {
                self.isPushToTalkKeyDown = false
                self.eventHandler(.keyUp, .pushToTalk)
            }
        }
    }

    private func convertModifiers(_ carbonModifiers: UInt32) -> NSEvent.ModifierFlags {
        var modifiers: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(optionKey) != 0 {
            modifiers.insert(.option)
        }
        if carbonModifiers & UInt32(controlKey) != 0 {
            modifiers.insert(.control)
        }
        if carbonModifiers & UInt32(shiftKey) != 0 {
            modifiers.insert(.shift)
        }
        if carbonModifiers & UInt32(cmdKey) != 0 {
            modifiers.insert(.command)
        }
        return modifiers
    }

    func unregisterHotkeys() {
        toggleHotKey = nil
        pushToTalkHotKey = nil
    }

    @discardableResult
    func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if !trusted {
            AppLogger.system.warning("Accessibility permission not granted")
        }

        return trusted
    }
}

// Hotkey recorder view for settings
import SwiftUI

struct HotkeyRecorderView: View {
    @EnvironmentObject var appState: AppState
    @Binding var config: HotkeyConfig
    let recorderId: String  // Unique identifier for this recorder
    @State private var localMonitor: Any?
    @State private var globalMonitor: Any?
    @State private var conflictMessage: String?

    private var isRecording: Bool {
        appState.activeHotkeyRecorder == recorderId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(isRecording ? "Press a key..." : config.displayString)
                    .frame(minWidth: 100)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isRecording ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                    .foregroundColor(config.isEmpty && !isRecording ? .secondary : .primary)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 2)
                    )

                Button(isRecording ? "Cancel" : "Record") {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                }
                .buttonStyle(.bordered)

                // Clear button - only show if hotkey is set and not recording
                if !config.isEmpty && !isRecording {
                    Button {
                        config = .empty
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear hotkey")
                }
            }

            if let message = appState.hotkeyConflictMessage(for: recorderId) {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .onDisappear {
            // Clean up monitors when view disappears
            if isRecording {
                stopRecording()
            }
        }
        .onChange(of: appState.activeHotkeyRecorder) { _, newValue in
            // If another recorder became active, clean up our monitors
            if newValue != recorderId {
                cleanupMonitors()
            }
        }
        .alert(
            "Hotkey Conflict",
            isPresented: Binding(
                get: { conflictMessage != nil },
                set: { if !$0 { conflictMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(conflictMessage ?? "")
        }
    }

    private func startRecording() {
        // Set this recorder as active (will automatically deactivate any other)
        appState.activeHotkeyRecorder = recorderId

        // Monitor for key events
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            self.handleKeyEvent(event)
            return nil // Consume the event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            self.handleKeyEvent(event)
        }
    }

    private func stopRecording() {
        appState.activeHotkeyRecorder = nil
        cleanupMonitors()
    }

    private func cleanupMonitors() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }

        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Only handle events if we're the active recorder
        guard isRecording else { return }

        // Ignore modifier-only events unless there's also a key
        if event.type == .flagsChanged {
            return
        }

        // Ignore escape - used to cancel
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        // Build modifiers
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if event.modifierFlags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if event.modifierFlags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if event.modifierFlags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }

        // Require at least one modifier for most keys (except F-keys)
        let isFunctionKey = event.keyCode >= UInt16(kVK_F1) && event.keyCode <= UInt16(kVK_F20)
        if modifiers == 0 && !isFunctionKey {
            return
        }

        let newConfig = HotkeyConfig(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        if let conflict = appState.hotkeyConflictMessage(for: recorderId, pendingConfig: newConfig) {
            conflictMessage = conflict
            stopRecording()
            return
        }

        config = newConfig
        stopRecording()
    }
}
