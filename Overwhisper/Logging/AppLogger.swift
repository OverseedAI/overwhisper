import Foundation
import os

enum AppLogger {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.overseed.overwhisper"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let transcription = Logger(subsystem: subsystem, category: "transcription")
    static let system = Logger(subsystem: subsystem, category: "system")
}
