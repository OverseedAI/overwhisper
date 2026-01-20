import AppKit
import Carbon.HIToolbox

class TextInserter {

    func insertText(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Save current clipboard contents
        let previousContents = pasteboard.string(forType: .string)

        // Copy transcription to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure clipboard is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
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
    }

    private func simulatePaste() {
        // Create event source
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            print("Failed to create event source")
            return
        }

        // V key code
        let vKeyCode: CGKeyCode = CGKeyCode(kVK_ANSI_V)

        // Create key down event with Command modifier
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) else {
            print("Failed to create key down event")
            return
        }
        keyDown.flags = .maskCommand

        // Create key up event
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            print("Failed to create key up event")
            return
        }
        keyUp.flags = .maskCommand

        // Post the events
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
