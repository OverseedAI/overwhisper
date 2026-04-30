import AVFoundation
import Foundation

struct TranscriptionDebugSession: Codable, Identifiable, Equatable {
  let id: UUID
  let timestamp: Date
  let engine: String
  let model: String
  let audioFileName: String?
  let audioFileSizeBytes: Int64?
  let audioDurationSeconds: Double?
  let recordingDurationSeconds: Double
  let transcribedText: String
  let latencySeconds: Double
  let language: String?
  let errorMessage: String?
  let usedCloudFallback: Bool

  var success: Bool { errorMessage == nil }
}

@MainActor
final class DebugSessionStore: ObservableObject {
  @Published private(set) var sessions: [TranscriptionDebugSession] = []

  private let maxSessions = 30
  private let metadataFileName = "sessions.json"
  private let audioDirectoryName = "audio"

  init() {
    load()
  }

  // MARK: - Paths

  var rootDirectory: URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first!
    let bundleId = Bundle.main.bundleIdentifier ?? "com.overseed.overwhisper"
    return support.appendingPathComponent(bundleId).appendingPathComponent("DebugSessions")
  }

  var audioDirectory: URL {
    rootDirectory.appendingPathComponent(audioDirectoryName)
  }

  private var metadataURL: URL {
    rootDirectory.appendingPathComponent(metadataFileName)
  }

  func audioURL(for session: TranscriptionDebugSession) -> URL? {
    guard let name = session.audioFileName else { return nil }
    let url = audioDirectory.appendingPathComponent(name)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  // MARK: - Mutations

  /// Records a session. If `sourceAudioURL` is provided, the audio file is moved
  /// into the debug audio directory (renamed to `<id>.wav`). The caller should not
  /// continue to reference the source file after a successful call.
  @discardableResult
  func record(
    engine: String,
    model: String,
    sourceAudioURL: URL?,
    recordingDuration: Double,
    transcribedText: String,
    latencySeconds: Double,
    language: String?,
    errorMessage: String?,
    usedCloudFallback: Bool
  ) -> TranscriptionDebugSession {
    let id = UUID()
    ensureDirectories()

    var storedFileName: String?
    var fileSize: Int64?
    var audioDuration: Double?

    if let src = sourceAudioURL {
      let dest = audioDirectory.appendingPathComponent("\(id.uuidString).wav")
      do {
        if FileManager.default.fileExists(atPath: dest.path) {
          try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: src, to: dest)
        storedFileName = dest.lastPathComponent
        let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path)
        fileSize = (attrs?[.size] as? NSNumber)?.int64Value
        audioDuration = Self.duration(of: dest)
      } catch {
        AppLogger.app.error("DebugSessionStore: failed to move audio: \(error.localizedDescription)")
      }
    }

    let session = TranscriptionDebugSession(
      id: id,
      timestamp: Date(),
      engine: engine,
      model: model,
      audioFileName: storedFileName,
      audioFileSizeBytes: fileSize,
      audioDurationSeconds: audioDuration,
      recordingDurationSeconds: recordingDuration,
      transcribedText: transcribedText,
      latencySeconds: latencySeconds,
      language: language,
      errorMessage: errorMessage,
      usedCloudFallback: usedCloudFallback
    )

    sessions.insert(session, at: 0)
    trim()
    persist()
    return session
  }

  /// Updates an existing session (e.g., when cloud fallback succeeds after a local failure).
  func update(_ session: TranscriptionDebugSession) {
    guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
    sessions[idx] = session
    persist()
  }

  func clear() {
    for session in sessions {
      if let url = audioURL(for: session) {
        try? FileManager.default.removeItem(at: url)
      }
    }
    sessions = []
    persist()
  }

  func delete(_ session: TranscriptionDebugSession) {
    if let url = audioURL(for: session) {
      try? FileManager.default.removeItem(at: url)
    }
    sessions.removeAll { $0.id == session.id }
    persist()
  }

  // MARK: - Persistence

  private func load() {
    guard FileManager.default.fileExists(atPath: metadataURL.path) else { return }
    do {
      let data = try Data(contentsOf: metadataURL)
      let decoded = try JSONDecoder.iso8601().decode([TranscriptionDebugSession].self, from: data)
      sessions = decoded
    } catch {
      AppLogger.app.error("DebugSessionStore: failed to load: \(error.localizedDescription)")
    }
  }

  private func persist() {
    ensureDirectories()
    do {
      let data = try JSONEncoder.iso8601().encode(sessions)
      try data.write(to: metadataURL, options: .atomic)
    } catch {
      AppLogger.app.error("DebugSessionStore: failed to persist: \(error.localizedDescription)")
    }
  }

  private func trim() {
    guard sessions.count > maxSessions else { return }
    let toRemove = sessions.suffix(sessions.count - maxSessions)
    for session in toRemove {
      if let url = audioURL(for: session) {
        try? FileManager.default.removeItem(at: url)
      }
    }
    sessions = Array(sessions.prefix(maxSessions))
  }

  private func ensureDirectories() {
    try? FileManager.default.createDirectory(
      at: audioDirectory, withIntermediateDirectories: true)
  }

  private static func duration(of url: URL) -> Double? {
    guard let file = try? AVAudioFile(forReading: url) else { return nil }
    let sampleRate = file.processingFormat.sampleRate
    guard sampleRate > 0 else { return nil }
    return Double(file.length) / sampleRate
  }
}

private extension JSONEncoder {
  static func iso8601() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }
}

private extension JSONDecoder {
  static func iso8601() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
