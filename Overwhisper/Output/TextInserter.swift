import AppKit

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

        // Save current clipboard contents
        let previousContents = pasteboard.string(forType: .string)

        // Copy transcription to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure clipboard is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            // Simulate Cmd+V
            self?.simulatePaste()

            // Restore original clipboard after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let prev = previousContents {
                    pasteboard.clearContents()
                    pasteboard.setString(prev, forType: .string)
                }
            }
        }

        return true
    }

    private func simulatePaste() {
        let script = """
            tell application "System Events"
                keystroke "v" using command down
            end tell
            """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                AppLogger.system.error("AppleScript paste failed: \(error)")
            }
        }
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
