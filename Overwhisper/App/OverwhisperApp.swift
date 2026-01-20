import SwiftUI
import AppKit

@main
struct OverwhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings are handled via NSWindow from AppDelegate
        // This empty Settings scene satisfies SwiftUI's requirement for at least one scene
        Settings {
            EmptyView()
        }
    }
}
