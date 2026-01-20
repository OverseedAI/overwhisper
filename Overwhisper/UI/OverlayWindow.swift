import AppKit
import SwiftUI

class OverlayWindow: NSPanel {
    private let appState: AppState
    private var hostingView: NSHostingView<OverlayView>?

    init(appState: AppState) {
        self.appState = appState

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 90),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Configure window properties
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false

        // Set up the SwiftUI content
        let overlayView = OverlayView(appState: appState)
        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.frame = self.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView
        self.hostingView = hostingView
    }

    func show(position: OverlayPosition) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let windowSize = self.frame.size
        let padding: CGFloat = 20

        var origin: NSPoint

        switch position {
        case .topLeft:
            origin = NSPoint(
                x: screenFrame.minX + padding,
                y: screenFrame.maxY - windowSize.height - padding
            )
        case .topRight:
            origin = NSPoint(
                x: screenFrame.maxX - windowSize.width - padding,
                y: screenFrame.maxY - windowSize.height - padding
            )
        case .bottomLeft:
            origin = NSPoint(
                x: screenFrame.minX + padding,
                y: screenFrame.minY + padding
            )
        case .bottomRight:
            origin = NSPoint(
                x: screenFrame.maxX - windowSize.width - padding,
                y: screenFrame.minY + padding
            )
        case .center:
            origin = NSPoint(
                x: screenFrame.midX - windowSize.width / 2,
                y: screenFrame.midY - windowSize.height / 2
            )
        }

        self.setFrameOrigin(origin)

        // Animate in
        self.alphaValue = 0
        self.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
    }

    func showTranscribing() {
        // The view will automatically update based on appState
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
}
