import XCTest

@testable import Overwhisper

final class TranscriptionDebugSessionTests: XCTestCase {
  private let original = TranscriptionDebugSession(
    id: UUID(),
    timestamp: Date(timeIntervalSince1970: 1_700_000_000),
    engine: "whisperKit",
    model: "WhisperKit small.en",
    audioFileName: "abc.wav",
    audioFileSizeBytes: 4_096,
    audioDurationSeconds: 2.5,
    recordingDurationSeconds: 2.6,
    transcribedText: "",
    latencySeconds: 1.2,
    language: nil,
    errorMessage: "Model failed to load",
    usedCloudFallback: false
  )

  func testWithResultPreservesIdentityAndAudioMetadata() {
    let updated = original.withResult(
      engine: "parakeet",
      model: "Parakeet v3",
      transcribedText: "hello world",
      latencySeconds: 0.4,
      language: "en",
      errorMessage: nil,
      usedCloudFallback: false
    )

    XCTAssertEqual(updated.id, original.id)
    XCTAssertEqual(updated.timestamp, original.timestamp)
    XCTAssertEqual(updated.audioFileName, original.audioFileName)
    XCTAssertEqual(updated.audioFileSizeBytes, original.audioFileSizeBytes)
    XCTAssertEqual(updated.audioDurationSeconds, original.audioDurationSeconds)
    XCTAssertEqual(updated.recordingDurationSeconds, original.recordingDurationSeconds)
  }

  func testWithResultReplacesResultFields() {
    let updated = original.withResult(
      engine: "parakeet",
      model: "Parakeet v3",
      transcribedText: "hello world",
      latencySeconds: 0.4,
      language: "en",
      errorMessage: nil,
      usedCloudFallback: true
    )

    XCTAssertEqual(updated.engine, "parakeet")
    XCTAssertEqual(updated.model, "Parakeet v3")
    XCTAssertEqual(updated.transcribedText, "hello world")
    XCTAssertEqual(updated.latencySeconds, 0.4)
    XCTAssertEqual(updated.language, "en")
    XCTAssertNil(updated.errorMessage)
    XCTAssertTrue(updated.usedCloudFallback)
    XCTAssertTrue(updated.success)
    XCTAssertFalse(original.success)
  }

  func testWithResultCanRecordANewFailure() {
    let updated = original.withResult(
      engine: original.engine,
      model: original.model,
      transcribedText: "",
      latencySeconds: 0.1,
      language: nil,
      errorMessage: "Cancelled by user",
      usedCloudFallback: false
    )

    XCTAssertEqual(updated.errorMessage, "Cancelled by user")
    XCTAssertFalse(updated.success)
    XCTAssertEqual(updated.id, original.id)
  }
}
