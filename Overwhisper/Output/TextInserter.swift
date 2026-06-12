import AppKit
import Carbon.HIToolbox

class TextInserter {

    /// Check if accessibility permission is granted
    static func hasAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Prompt the user to grant accessibility permission
    /// Returns true if permission is already granted
    static func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Delay before simulating Cmd+V so the target app sees the new pasteboard contents.
    private static let pasteDelay: TimeInterval = 0.15
    /// Delay before restoring the previous clipboard. Slow apps read the pasteboard
    /// noticeably after the Cmd+V event lands; restoring too early pastes the old clipboard.
    private static let restoreDelay: TimeInterval = 0.3

    /// Insert text at the current cursor position
    /// Returns true if auto-paste was attempted, false if text was only copied to clipboard
    @discardableResult
    func insertText(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general

        // Check accessibility permission before attempting paste
        guard Self.hasAccessibilityPermission() else {
            // No permission - just copy to clipboard (don't restore previous)
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            AppLogger.system.warning("Accessibility permission not granted - text copied to clipboard only")
            return false
        }

        // Snapshot every item and every representation (images, files, RTF, ...)
        // — restoring only the plain string destroys non-text clipboards.
        let savedItems = Self.snapshot(pasteboard)

        // Copy transcription to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let transcriptChangeCount = pasteboard.changeCount

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteDelay) { [weak self] in
            self?.simulatePaste()

            DispatchQueue.main.asyncAfter(deadline: .now() + Self.restoreDelay) {
                // If the user or another app wrote to the clipboard meanwhile,
                // restoring would stomp their copy — leave it alone.
                guard pasteboard.changeCount == transcriptChangeCount else { return }
                guard !savedItems.isEmpty else { return }

                pasteboard.clearContents()
                pasteboard.writeObjects(savedItems)
            }
        }

        return true
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private func simulatePaste() {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            AppLogger.system.error("Failed to create event source")
            return
        }

        let vKeyCode: CGKeyCode = CGKeyCode(kVK_ANSI_V)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) else {
            AppLogger.system.error("Failed to create key down event")
            return
        }
        keyDown.flags = .maskCommand

        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            AppLogger.system.error("Failed to create key up event")
            return
        }
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // Alternative method using Accessibility API (more reliable in some apps)
    func insertTextViaAccessibility(_ text: String) {
        let systemWideElement = AXUIElementCreateSystemWide()

        var focusedElement: AnyObject?
        let error = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard error == .success, let element = focusedElement else {
            // Fall back to clipboard method
            insertText(text)
            return
        }

        // Try to set the value directly
        let setError = AXUIElementSetAttributeValue(
            element as! AXUIElement,
            kAXValueAttribute as CFString,
            text as CFTypeRef
        )

        if setError != .success {
            // Fall back to clipboard method
            insertText(text)
        }
    }
}
