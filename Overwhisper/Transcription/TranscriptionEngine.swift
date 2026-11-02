import Foundation

protocol TranscriptionEngine: Sendable {
    func transcribe(audioURL: URL) async throws -> String
}

struct TranscriptionResult {
    let text: String
    let language: String?
    let confidence: Float?
    let segments: [TranscriptionSegment]?
}

struct TranscriptionSegment {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

/// The picker and engine switches use the same language capabilities.
enum TranscriptionLanguagePolicy {
    static let parakeetV3 = [
        ("auto", "Auto-detect"),
        ("bg", "Bulgarian"),
        ("hr", "Croatian"),
        ("cs", "Czech"),
        ("da", "Danish"),
        ("nl", "Dutch"),
        ("en", "English"),
        ("et", "Estonian"),
        ("fi", "Finnish"),
        ("fr", "French"),
        ("de", "German"),
        ("el", "Greek"),
        ("hu", "Hungarian"),
        ("it", "Italian"),
        ("lv", "Latvian"),
        ("lt", "Lithuanian"),
        ("mt", "Maltese"),
        ("pl", "Polish"),
        ("pt", "Portuguese"),
        ("ro", "Romanian"),
        ("sk", "Slovak"),
        ("sl", "Slovenian"),
        ("es", "Spanish"),
        ("sv", "Swedish"),
        ("ru", "Russian"),
        ("uk", "Ukrainian")
    ]

    static func choices(engine: TranscriptionEngineType, parakeet: ParakeetModelType) -> [(String, String)] {
        guard engine == .parakeet else { return WhisperLanguages.all }
        return parakeet == .v2English ? [("en", "English")] : parakeetV3
    }

    static func normalized(_ language: String, engine: TranscriptionEngineType, parakeet: ParakeetModelType) -> String {
        let codes = choices(engine: engine, parakeet: parakeet).map(\.0)
        return codes.contains(language) ? language : (codes.contains("auto") ? "auto" : "en")
    }
}
