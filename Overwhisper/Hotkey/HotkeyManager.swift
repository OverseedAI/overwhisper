import AppKit
import Carbon.HIToolbox
import HotKey

enum HotkeyEvent {
    case keyDown
    case keyUp
}

@MainActor
class HotkeyManager {
    private var hotKey: HotKey?
    private let appState: AppState
    private let eventHandler: (HotkeyEvent) -> Void

    // For push-to-talk, we need to track key up events
    nonisolated(unsafe) private var globalMonitor: Any?
    nonisolated(unsafe) private var localMonitor: Any?
    private var isKeyDown = false

    init(appState: AppState, eventHandler: @escaping (HotkeyEvent) -> Void) {
        self.appState = appState
        self.eventHandler = eventHandler

        registerHotkey(config: appState.hotkeyConfig)
        _ = checkAccessibilityPermission()
    }

    func registerHotkey(config: HotkeyConfig) {
        unregisterHotkey()

        // Convert our config to HotKey library format
        guard let key = Key(carbonKeyCode: UInt32(config.keyCode)) else {
            print("Invalid key code: \(config.keyCode)")
            return
        }

        var modifiers: NSEvent.ModifierFlags = []
        if config.modifiers & UInt32(optionKey) != 0 {
            modifiers.insert(.option)
        }
        if config.modifiers & UInt32(controlKey) != 0 {
            modifiers.insert(.control)
        }
        if config.modifiers & UInt32(shiftKey) != 0 {
            modifiers.insert(.shift)
        }
        if config.modifiers & UInt32(cmdKey) != 0 {
            modifiers.insert(.command)
        }

        hotKey = HotKey(key: key, modifiers: modifiers)

        hotKey?.keyDownHandler = { [weak self] in
            guard let self = self else { return }
            self.isKeyDown = true
            self.eventHandler(.keyDown)
        }

        hotKey?.keyUpHandler = { [weak self] in
            guard let self = self else { return }
            if self.isKeyDown {
                self.isKeyDown = false
                self.eventHandler(.keyUp)
            }
        }
    }

    func unregisterHotkey() {
        hotKey = nil

        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }

        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    @discardableResult
    func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if !trusted {
            print("Accessibility permission not granted")
        }

        return trusted
    }
}

// Hotkey recorder view for settings
import SwiftUI

struct HotkeyRecorderView: View {
    @Binding var config: HotkeyConfig
    @State private var isRecording = false
    @State private var localMonitor: Any?
    @State private var globalMonitor: Any?

    var body: some View {
        HStack {
            Text(isRecording ? "Press a key..." : config.displayString)
                .frame(minWidth: 100)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isRecording ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
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
        }
    }

    private func startRecording() {
        isRecording = true

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
        isRecording = false

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

        config = HotkeyConfig(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        stopRecording()
    }
}
