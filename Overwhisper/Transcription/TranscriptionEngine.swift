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
