import Foundation
import Combine
import SwiftUI
import Carbon.HIToolbox

struct DebugLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: DebugLogLevel
    let message: String
    let source: String

    enum DebugLogLevel: String {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"

        var color: String {
            switch self {
            case .info: return "blue"
            case .warning: return "orange"
            case .error: return "red"
            }
        }
    }
}

enum RecordingState: Equatable {
    case idle
    case recording
    case transcribing
    case error(String)

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
}

enum RecordingMode: String, CaseIterable, Identifiable {
    case pushToTalk = "Push-to-Talk"
    case toggle = "Toggle"

    var id: String { rawValue }
}

enum OverlayPosition: String, CaseIterable, Identifiable {
    case topLeft = "Top Left"
    case topCenter = "Top Center"
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomCenter = "Bottom Center"
    case bottomRight = "Bottom Right"

    var id: String { rawValue }

    // Grid layout helpers
    static var topRow: [OverlayPosition] { [.topLeft, .topCenter, .topRight] }
    static var bottomRow: [OverlayPosition] { [.bottomLeft, .bottomCenter, .bottomRight] }
}

enum TranscriptionEngineType: String, CaseIterable, Identifiable {
    case whisperKit = "WhisperKit (Local)"
    case openAI = "OpenAI API"

    var id: String { rawValue }
}

enum WhisperModel: String, CaseIterable, Identifiable {
    // English-only models (faster, more accurate for English)
    case smallEn = "small.en"
    case mediumEn = "medium.en"
    // Multilingual models (supports 99+ languages including Korean, Japanese, Chinese, etc.)
    case small = "small"
    case medium = "medium"
    case large = "large-v3_turbo"

    var id: String { rawValue }

    var isEnglishOnly: Bool {
        switch self {
        case .smallEn, .mediumEn: return true
        case .small, .medium, .large: return false
        }
    }

    var displayName: String {
        switch self {
        case .smallEn: return "Small"
        case .mediumEn: return "Medium"
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    var size: String {
        switch self {
        case .smallEn, .small: return "~500 MB"
        case .mediumEn, .medium: return "~1.5 GB"
        case .large: return "~1.6 GB"
        }
    }

    static var englishModels: [WhisperModel] {
        [.smallEn, .mediumEn]
    }

    static var multilingualModels: [WhisperModel] {
        [.small, .medium, .large]
    }
}

struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    // Default: Option+Space for toggle, Option+Shift+Space for push-to-talk
    static let defaultToggle = HotkeyConfig(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
    static let defaultPushToTalk = HotkeyConfig(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | shiftKey))

    // Empty/not set state - keyCode 0xFFFF is unused
    static let empty = HotkeyConfig(keyCode: 0xFFFF, modifiers: 0)

    // Legacy default for migration
    static let `default` = defaultToggle

    var isEmpty: Bool {
        keyCode == 0xFFFF
    }

    var displayString: String {
        if isEmpty {
            return "Not set"
        }

        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }

        let keyName = keyCodeToString(keyCode)
        parts.append(keyName)

        return parts.joined()
    }

    private func keyCodeToString(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        case kVK_Escape: return "Esc"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        default: return "Key\(keyCode)"
        }
    }
}

@MainActor
class AppState: ObservableObject {
    // Recording state
    @Published var recordingState: RecordingState = .idle
    @Published var audioLevel: Float = 0.0
    @Published var recordingDuration: TimeInterval = 0.0

    // Settings
    @Published var recordingMode: RecordingMode {
        didSet { UserDefaults.standard.set(recordingMode.rawValue, forKey: "recordingMode") }
    }
    @Published var overlayPosition: OverlayPosition {
        didSet { UserDefaults.standard.set(overlayPosition.rawValue, forKey: "overlayPosition") }
    }
    @Published var transcriptionEngine: TranscriptionEngineType {
        didSet { UserDefaults.standard.set(transcriptionEngine.rawValue, forKey: "transcriptionEngine") }
    }
    @Published var whisperModel: WhisperModel {
        didSet { UserDefaults.standard.set(whisperModel.rawValue, forKey: "whisperModel") }
    }
    @Published var language: String {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }
    @Published var enableCloudFallback: Bool {
        didSet { UserDefaults.standard.set(enableCloudFallback, forKey: "enableCloudFallback") }
    }
    @Published var openAIAPIKey: String {
        didSet {
            try? KeychainHelper.save(key: "openAIAPIKey", data: openAIAPIKey.data(using: .utf8) ?? Data())
        }
    }
    @Published var playSoundOnCompletion: Bool {
        didSet { UserDefaults.standard.set(playSoundOnCompletion, forKey: "playSoundOnCompletion") }
    }
    @Published var playSoundOnStart: Bool {
        didSet { UserDefaults.standard.set(playSoundOnStart, forKey: "playSoundOnStart") }
    }
    @Published var showNotificationOnError: Bool {
        didSet { UserDefaults.standard.set(showNotificationOnError, forKey: "showNotificationOnError") }
    }
    @Published var muteSystemAudioWhileRecording: Bool {
        didSet { UserDefaults.standard.set(muteSystemAudioWhileRecording, forKey: "muteSystemAudioWhileRecording") }
    }
    @Published var startAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(startAtLogin, forKey: "startAtLogin")
            LaunchAtLogin.isEnabled = startAtLogin
        }
    }
    @Published var toggleHotkeyConfig: HotkeyConfig {
        didSet {
            if let data = try? JSONEncoder().encode(toggleHotkeyConfig) {
                UserDefaults.standard.set(data, forKey: "toggleHotkeyConfig")
            }
        }
    }
    @Published var pushToTalkHotkeyConfig: HotkeyConfig {
        didSet {
            if let data = try? JSONEncoder().encode(pushToTalkHotkeyConfig) {
                UserDefaults.standard.set(data, forKey: "pushToTalkHotkeyConfig")
            }
        }
    }

    // Legacy property for backwards compatibility
    var hotkeyConfig: HotkeyConfig {
        get { toggleHotkeyConfig }
        set { toggleHotkeyConfig = newValue }
    }

    // Model state
    @Published var isModelDownloaded: Bool = false
    @Published var modelDownloadProgress: Double = 0.0
    @Published var isDownloadingModel: Bool = false
    @Published var isInitializingEngine: Bool = false
    @Published var downloadedModels: Set<String> = []
    @Published var currentlyDownloadingModel: String?

    // Last transcription result
    @Published var lastTranscription: String = ""
    @Published var lastError: String?

    // Debug mode
    @Published var debugModeEnabled: Bool {
        didSet { UserDefaults.standard.set(debugModeEnabled, forKey: "debugModeEnabled") }
    }
    @Published var debugLogs: [DebugLogEntry] = []
    private let maxDebugLogs = 100

    // Hotkey recording state - tracks which recorder is active (nil if none)
    @Published var activeHotkeyRecorder: String?

    private var recordingTimer: Timer?

    init() {
        // Load settings from UserDefaults
        let modeStr = UserDefaults.standard.string(forKey: "recordingMode") ?? RecordingMode.toggle.rawValue
        self.recordingMode = RecordingMode(rawValue: modeStr) ?? .toggle

        let posStr = UserDefaults.standard.string(forKey: "overlayPosition") ?? OverlayPosition.bottomRight.rawValue
        self.overlayPosition = OverlayPosition(rawValue: posStr) ?? .bottomRight

        let engineStr = UserDefaults.standard.string(forKey: "transcriptionEngine") ?? TranscriptionEngineType.whisperKit.rawValue
        self.transcriptionEngine = TranscriptionEngineType(rawValue: engineStr) ?? .whisperKit

        let modelStr = UserDefaults.standard.string(forKey: "whisperModel") ?? WhisperModel.smallEn.rawValue
        self.whisperModel = WhisperModel(rawValue: modelStr) ?? .smallEn

        self.language = UserDefaults.standard.string(forKey: "language") ?? "auto"
        self.enableCloudFallback = UserDefaults.standard.bool(forKey: "enableCloudFallback")

        if let apiKeyData = try? KeychainHelper.load(key: "openAIAPIKey"),
           let apiKey = String(data: apiKeyData, encoding: .utf8) {
            self.openAIAPIKey = apiKey
        } else {
            self.openAIAPIKey = ""
        }

        self.playSoundOnCompletion = UserDefaults.standard.object(forKey: "playSoundOnCompletion") as? Bool ?? true
        self.playSoundOnStart = UserDefaults.standard.bool(forKey: "playSoundOnStart")
        self.showNotificationOnError = UserDefaults.standard.object(forKey: "showNotificationOnError") as? Bool ?? true
        self.muteSystemAudioWhileRecording = UserDefaults.standard.bool(forKey: "muteSystemAudioWhileRecording")
        self.startAtLogin = UserDefaults.standard.bool(forKey: "startAtLogin")

        // Load toggle hotkey (with migration from legacy hotkeyConfig)
        if let hotkeyData = UserDefaults.standard.data(forKey: "toggleHotkeyConfig"),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: hotkeyData) {
            self.toggleHotkeyConfig = config
        } else if let legacyData = UserDefaults.standard.data(forKey: "hotkeyConfig"),
                  let legacyConfig = try? JSONDecoder().decode(HotkeyConfig.self, from: legacyData) {
            // Migrate from legacy single hotkey
            self.toggleHotkeyConfig = legacyConfig
        } else {
            self.toggleHotkeyConfig = .defaultToggle
        }

        // Load push-to-talk hotkey
        if let hotkeyData = UserDefaults.standard.data(forKey: "pushToTalkHotkeyConfig"),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: hotkeyData) {
            self.pushToTalkHotkeyConfig = config
        } else {
            self.pushToTalkHotkeyConfig = .defaultPushToTalk
        }

        self.debugModeEnabled = UserDefaults.standard.bool(forKey: "debugModeEnabled")
    }

    func addDebugLog(_ message: String, level: DebugLogEntry.DebugLogLevel = .info, source: String = "App") {
        guard debugModeEnabled else { return }
        let entry = DebugLogEntry(timestamp: Date(), level: level, message: message, source: source)
        debugLogs.insert(entry, at: 0)
        if debugLogs.count > maxDebugLogs {
            debugLogs.removeLast()
        }
    }

    func clearDebugLogs() {
        debugLogs.removeAll()
    }

    func startRecordingTimer() {
        recordingDuration = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordingDuration += 0.1
            }
        }
    }

    func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
}

// Keychain helper for secure API key storage
enum KeychainHelper {
    static func save(key: String, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw NSError(domain: "KeychainError", code: Int(status))
        }
    }

    static func load(key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw NSError(domain: "KeychainError", code: Int(status))
        }

        return data
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// Launch at login helper
enum LaunchAtLogin {
    static var isEnabled: Bool {
        get {
            // Check if launch agent exists
            if Bundle.main.bundleIdentifier != nil {
                return SMAppService.mainApp.status == .enabled
            }
            return false
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to set launch at login: \(error)")
            }
        }
    }
}

import ServiceManagement

// System audio control via AppleScript (requires non-sandboxed app)
// Note: This only works with built-in audio or audio devices that support macOS volume controls.
// External audio interfaces (like Focusrite Scarlett) may not support mute/volume control.
enum SystemAudioManager {
    private static var wasSystemMuted = false
    private static var previousVolume: Int = 0
    private static var supportChecked = false
    private static var isSupported = false

    static func muteSystemAudio() {
        // Check if volume control is supported
        guard checkSupport() else {
            print("[SystemAudioManager] Volume control not supported on current audio device")
            return
        }

        // First, check if already muted
        if let muted = isSystemMuted(), muted {
            wasSystemMuted = true
            print("[SystemAudioManager] System already muted")
            return
        }

        wasSystemMuted = false

        // Try mute command first
        if setSystemMuted(true) {
            print("[SystemAudioManager] Muted using mute command")
            return
        }

        // Fallback: set volume to 0
        if let currentVolume = getSystemVolume() {
            previousVolume = currentVolume
            if setSystemVolume(0) {
                print("[SystemAudioManager] Muted by setting volume to 0 (was \(previousVolume))")
            }
        }
    }

    static func restoreSystemAudio() {
        guard checkSupport() else {
            return
        }

        if wasSystemMuted {
            print("[SystemAudioManager] System was muted before recording, not restoring")
            return
        }

        // Try unmute command first
        if setSystemMuted(false) {
            print("[SystemAudioManager] Unmuted using mute command")
            return
        }

        // Fallback: restore previous volume
        if previousVolume > 0 {
            if setSystemVolume(previousVolume) {
                print("[SystemAudioManager] Restored volume to \(previousVolume)")
            }
        }
    }

    private static func checkSupport() -> Bool {
        if supportChecked {
            return isSupported
        }
        supportChecked = true

        // Try to get the current volume - if it returns nil, volume control is not supported
        if let volume = getSystemVolume() {
            isSupported = true
            print("[SystemAudioManager] Volume control supported (current volume: \(volume))")
        } else {
            isSupported = false
            print("[SystemAudioManager] Volume control not supported (external audio interface?)")
        }
        return isSupported
    }

    private static func isSystemMuted() -> Bool? {
        let script = NSAppleScript(source: "output muted of (get volume settings)")
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        if error != nil {
            return nil
        }
        // Check for "missing value" by seeing if we can get a boolean
        let descriptor = result?.coerce(toDescriptorType: typeBoolean)
        if descriptor == nil {
            return nil
        }
        return result?.booleanValue
    }

    private static func getSystemVolume() -> Int? {
        let script = NSAppleScript(source: "output volume of (get volume settings)")
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        if error != nil {
            return nil
        }
        // Check for "missing value" by trying to coerce to integer
        let descriptor = result?.coerce(toDescriptorType: typeSInt32)
        if descriptor == nil {
            return nil
        }
        return Int(result?.int32Value ?? 0)
    }

    @discardableResult
    private static func setSystemMuted(_ muted: Bool) -> Bool {
        let script = NSAppleScript(source: "set volume output muted \(muted)")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        return error == nil
    }

    @discardableResult
    private static func setSystemVolume(_ volume: Int) -> Bool {
        let script = NSAppleScript(source: "set volume output volume \(volume)")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        return error == nil
    }
}
