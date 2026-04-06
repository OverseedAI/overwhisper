import SwiftUI
import AppKit

struct TutorialOverlayWindow: NSViewRepresentable {
    let position: OverlayPosition
    let onDismiss: () -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = TutorialOverlayNSView()
        view.position = position
        view.onDismiss = onDismiss
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class TutorialOverlayNSView: NSView {
    var position: OverlayPosition = .bottomRight
    var onDismiss: (() -> Void)?
    
    private var dismissWorkItem: DispatchWorkItem?
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        guard let window = self.window else { return }
        
        // Configure window
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        
        // Position the window
        positionWindow(window)
        
        // Auto-dismiss after 4 seconds
        dismissWorkItem = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        if let workItem = dismissWorkItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: workItem)
        }
    }
    
    private func positionWindow(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let windowSize = window.frame.size
        let padding: CGFloat = 20
        
        var origin: NSPoint
        
        switch position {
        case .topLeft:
            origin = NSPoint(
                x: screenFrame.minX + padding,
                y: screenFrame.maxY - windowSize.height - padding
            )
        case .topCenter:
            origin = NSPoint(
                x: screenFrame.midX - windowSize.width / 2,
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
        case .bottomCenter:
            origin = NSPoint(
                x: screenFrame.midX - windowSize.width / 2,
                y: screenFrame.minY + padding
            )
        case .bottomRight:
            origin = NSPoint(
                x: screenFrame.maxX - windowSize.width - padding,
                y: screenFrame.minY + padding
            )
        }
        
        window.setFrameOrigin(origin)
    }
    
    private func dismiss() {
        onDismiss?()
    }
}

struct TutorialOverlayView: View {
    @State private var showIndicator = false
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Arrow pointing to the overlay position
            Image(systemName: "arrow.down")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
                .opacity(showIndicator ? 1 : 0)
                .offset(y: showIndicator ? 0 : -10)
            
            // Tutorial card
            VStack(spacing: 8) {
                Text("Recording Overlay")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("Your transcription will appear here when recording")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 16) {
                    Label("Press hotkey to start", systemImage: "mic.fill")
                    Label("Press again to stop", systemImage: "stop.fill")
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.85))
                    .shadow(radius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3).delay(0.2)) {
                showIndicator = true
            }
        }
        .onTapGesture {
            onDismiss()
        }
    }
}

// Manager for showing/hiding tutorial
@MainActor
class TutorialManager {
    static let shared = TutorialManager()
    
    private var tutorialWindow: NSWindow?
    
    func showTutorial(position: OverlayPosition, onComplete: @escaping () -> Void) {
        // Don't show if already shown before
        guard !UserDefaults.standard.bool(forKey: "hasSeenTutorial") else {
            onComplete()
            return
        }
        
        // Mark as shown
        UserDefaults.standard.set(true, forKey: "hasSeenTutorial")
        
        // Create tutorial window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        
        let view = TutorialOverlayView(onDismiss: { [weak self] in
            self?.hideTutorial()
            onComplete()
        })
        
        window.contentView = NSHostingView(rootView: view)
        
        // Position window
        positionWindow(window, at: position)
        
        window.makeKeyAndOrderFront(nil)
        tutorialWindow = window
        
        // Auto-hide after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.hideTutorial()
            onComplete()
        }
    }
    
    private func positionWindow(_ window: NSWindow, at position: OverlayPosition) {
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let windowSize = window.frame.size
        let padding: CGFloat = 20
        let offset: CGFloat = 100 // Offset from the actual overlay position
        
        var origin: NSPoint
        
        switch position {
        case .topLeft:
            origin = NSPoint(
                x: screenFrame.minX + padding,
                y: screenFrame.maxY - windowSize.height - padding - offset
            )
        case .topCenter:
            origin = NSPoint(
                x: screenFrame.midX - windowSize.width / 2,
                y: screenFrame.maxY - windowSize.height - padding - offset
            )
        case .topRight:
            origin = NSPoint(
                x: screenFrame.maxX - windowSize.width - padding,
                y: screenFrame.maxY - windowSize.height - padding - offset
            )
        case .bottomLeft:
            origin = NSPoint(
                x: screenFrame.minX + padding,
                y: screenFrame.minY + padding + offset
            )
        case .bottomCenter:
            origin = NSPoint(
                x: screenFrame.midX - windowSize.width / 2,
                y: screenFrame.minY + padding + offset
            )
        case .bottomRight:
            origin = NSPoint(
                x: screenFrame.maxX - windowSize.width - padding,
                y: screenFrame.minY + padding + offset
            )
        }
        
        window.setFrameOrigin(origin)
    }
    
    private func hideTutorial() {
        tutorialWindow?.orderOut(nil)
        tutorialWindow = nil
    }
}

// Extension to reset tutorial (for testing)
extension TutorialManager {
    func resetTutorial() {
        UserDefaults.standard.set(false, forKey: "hasSeenTutorial")
    }
}
