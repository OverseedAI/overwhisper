import AppKit
import Carbon.HIToolbox
import HotKey
import SwiftUI

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

// MARK: - Hotkey Recorder View

struct HotkeyRecorderView: View {
    @EnvironmentObject var appState: AppState
    @Binding var config: HotkeyConfig
    let recorderId: String
    @State private var conflictMessage: String?
    @State private var isRecording: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            // Key capture field - becomes first responder when recording
            KeyCaptureField(
                isRecording: $isRecording,
                displayText: isRecording ? "Listening..." : config.displayString,
                onKeyCapture: { keyCode, modifiers in
                    handleCapturedKey(keyCode: keyCode, modifiers: modifiers)
                },
                onCancel: {
                    stopRecording()
                }
            )
            .frame(minWidth: 120, minHeight: 32)

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
        isRecording = true
    }

    private func stopRecording() {
        isRecording = false
    }

    private func handleCapturedKey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        // Ignore escape - used to cancel
        if keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        // Build carbon modifiers
        var carbonModifiers: UInt32 = 0
        if modifiers.contains(.option) {
            carbonModifiers |= UInt32(optionKey)
        }
        if modifiers.contains(.control) {
            carbonModifiers |= UInt32(controlKey)
        }
        if modifiers.contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
        }
        if modifiers.contains(.command) {
            carbonModifiers |= UInt32(cmdKey)
        }

        // Require at least one modifier for most keys (except F-keys)
        let isFunctionKey = keyCode >= UInt16(kVK_F1) && keyCode <= UInt16(kVK_F20)
        if carbonModifiers == 0 && !isFunctionKey {
            return
        }

        let newConfig = HotkeyConfig(keyCode: UInt32(keyCode), modifiers: carbonModifiers)
        if let conflict = appState.hotkeyConflictMessage(for: recorderId, pendingConfig: newConfig) {
            conflictMessage = conflict
            stopRecording()
            return
        }

        config = newConfig
        stopRecording()
    }
}

// MARK: - Key Capture Field (AppKit-based)

struct KeyCaptureField: NSViewRepresentable {
    @Binding var isRecording: Bool
    let displayText: String
    let onKeyCapture: (UInt16, NSEvent.ModifierFlags) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKeyCapture = onKeyCapture
        view.onCancel = onCancel
        view.displayText = displayText
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.isRecording = isRecording
        nsView.displayText = displayText
        nsView.updateAppearance()
        
        if isRecording {
            // Small delay to ensure the view is in the window hierarchy
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: KeyCaptureNSViewDelegate {
        func keyCaptureViewDidBecomeFirstResponder(_ view: KeyCaptureNSView) {
            // Optional: notify when view is ready
        }
    }
}

protocol KeyCaptureNSViewDelegate: AnyObject {
    func keyCaptureViewDidBecomeFirstResponder(_ view: KeyCaptureNSView)
}

class KeyCaptureNSView: NSView {
    var onKeyCapture: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    var onCancel: (() -> Void)?
    weak var delegate: KeyCaptureNSViewDelegate?
    
    var isRecording: Bool = false
    var displayText: String = ""
    
    private var textField: NSTextField!
    private var listeningIndicator: NSView?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        
        // Create text field for display
        let field = NSTextField(labelWithString: "")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.alignment = .center
        field.font = NSFont.systemFont(ofSize: 13)
        field.isSelectable = false
        addSubview(field)
        
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            field.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        textField = field
        updateAppearance()
    }

    func updateAppearance() {
        if isRecording {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.borderWidth = 2
            textField.stringValue = "Listening..."
            textField.textColor = .controlAccentColor
            showListeningIndicator()
        } else {
            layer?.backgroundColor = NSColor.secondarySystemFill.cgColor
            layer?.borderColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
            textField.stringValue = displayText
            textField.textColor = displayText == "Not set" ? .secondaryLabelColor : .controlTextColor
            hideListeningIndicator()
        }
    }
    
    private func showListeningIndicator() {
        hideListeningIndicator()
        
        let indicator = NSView()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.wantsLayer = true
        indicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        indicator.layer?.cornerRadius = 3
        addSubview(indicator)
        
        NSLayoutConstraint.activate([
            indicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            indicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            indicator.widthAnchor.constraint(equalToConstant: 6),
            indicator.heightAnchor.constraint(equalToConstant: 6)
        ])
        
        listeningIndicator = indicator
        
        // Animate the indicator
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.3
        animation.duration = 0.6
        animation.autoreverses = true
        animation.repeatCount = .infinity
        indicator.layer?.add(animation, forKey: "pulse")
    }
    
    private func hideListeningIndicator() {
        listeningIndicator?.removeFromSuperview()
        listeningIndicator = nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let success = super.becomeFirstResponder()
        if success {
            delegate?.keyCaptureViewDidBecomeFirstResponder(self)
        }
        return success
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Ignore escape - used to cancel
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }

        // Capture the key
        onKeyCapture?(event.keyCode, event.modifierFlags)
    }

    override func flagsChanged(with event: NSEvent) {
        // Just pass through - we capture modifiers with keyDown
        super.flagsChanged(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if isRecording {
            window?.makeFirstResponder(self)
        }
    }
}
