import Foundation
import Combine
import SwiftUI
import Carbon.HIToolbox

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
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"
    case center = "Center"

    var id: String { rawValue }
}

enum TranscriptionEngineType: String, CaseIterable, Identifiable {
    case whisperKit = "WhisperKit (Local)"
    case openAI = "OpenAI API"

    var id: String { rawValue }
}

enum WhisperModel: String, CaseIterable, Identifiable {
    case tiny = "tiny"
    case tinyEn = "tiny.en"
    case base = "base"
    case baseEn = "base.en"
    case small = "small"
    case smallEn = "small.en"
    case medium = "medium"
    case mediumEn = "medium.en"
    case large = "large-v3"
    case largeTurbo = "large-v3-turbo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny: return "Tiny (39M)"
        case .tinyEn: return "Tiny English (39M)"
        case .base: return "Base (74M)"
        case .baseEn: return "Base English (74M)"
        case .small: return "Small (244M)"
        case .smallEn: return "Small English (244M)"
        case .medium: return "Medium (769M)"
        case .mediumEn: return "Medium English (769M)"
        case .large: return "Large v3 (1.5B)"
        case .largeTurbo: return "Large v3 Turbo (809M)"
        }
    }
}

struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = HotkeyConfig(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))

    var displayString: String {
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
    @Published var showNotificationOnError: Bool {
        didSet { UserDefaults.standard.set(showNotificationOnError, forKey: "showNotificationOnError") }
    }
    @Published var startAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(startAtLogin, forKey: "startAtLogin")
            LaunchAtLogin.isEnabled = startAtLogin
        }
    }
    @Published var hotkeyConfig: HotkeyConfig {
        didSet {
            if let data = try? JSONEncoder().encode(hotkeyConfig) {
                UserDefaults.standard.set(data, forKey: "hotkeyConfig")
            }
        }
    }

    // Model state
    @Published var isModelDownloaded: Bool = false
    @Published var modelDownloadProgress: Double = 0.0
    @Published var isDownloadingModel: Bool = false

    // Last transcription result
    @Published var lastTranscription: String = ""
    @Published var lastError: String?

    private var recordingTimer: Timer?

    init() {
        // Load settings from UserDefaults
        let modeStr = UserDefaults.standard.string(forKey: "recordingMode") ?? RecordingMode.toggle.rawValue
        self.recordingMode = RecordingMode(rawValue: modeStr) ?? .toggle

        let posStr = UserDefaults.standard.string(forKey: "overlayPosition") ?? OverlayPosition.bottomRight.rawValue
        self.overlayPosition = OverlayPosition(rawValue: posStr) ?? .bottomRight

        let engineStr = UserDefaults.standard.string(forKey: "transcriptionEngine") ?? TranscriptionEngineType.whisperKit.rawValue
        self.transcriptionEngine = TranscriptionEngineType(rawValue: engineStr) ?? .whisperKit

        let modelStr = UserDefaults.standard.string(forKey: "whisperModel") ?? WhisperModel.baseEn.rawValue
        self.whisperModel = WhisperModel(rawValue: modelStr) ?? .baseEn

        self.language = UserDefaults.standard.string(forKey: "language") ?? "auto"
        self.enableCloudFallback = UserDefaults.standard.bool(forKey: "enableCloudFallback")

        if let apiKeyData = try? KeychainHelper.load(key: "openAIAPIKey"),
           let apiKey = String(data: apiKeyData, encoding: .utf8) {
            self.openAIAPIKey = apiKey
        } else {
            self.openAIAPIKey = ""
        }

        self.playSoundOnCompletion = UserDefaults.standard.object(forKey: "playSoundOnCompletion") as? Bool ?? true
        self.showNotificationOnError = UserDefaults.standard.object(forKey: "showNotificationOnError") as? Bool ?? true
        self.startAtLogin = UserDefaults.standard.bool(forKey: "startAtLogin")

        if let hotkeyData = UserDefaults.standard.data(forKey: "hotkeyConfig"),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: hotkeyData) {
            self.hotkeyConfig = config
        } else {
            self.hotkeyConfig = .default
        }
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
