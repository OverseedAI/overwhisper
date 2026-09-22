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

// MARK: - Retention policy

/// How long a recording (audio + metadata) is kept before it is deleted.
enum AudioRetentionAge: String, CaseIterable, Identifiable {
  case oneDay = "1d"
  case sevenDays = "7d"
  case thirtyDays = "30d"
  case ninetyDays = "90d"
  case never = "never"

  var id: String { rawValue }

  var label: String {
    switch self {
    case .oneDay: return "1 day"
    case .sevenDays: return "7 days"
    case .thirtyDays: return "30 days"
    case .ninetyDays: return "90 days"
    case .never: return "Never"
    }
  }

  /// Maximum age in seconds, or `nil` to keep recordings forever.
  var maxAge: TimeInterval? {
    switch self {
    case .oneDay: return 1 * 86_400
    case .sevenDays: return 7 * 86_400
    case .thirtyDays: return 30 * 86_400
    case .ninetyDays: return 90 * 86_400
    case .never: return nil
    }
  }
}

/// Upper bound on how many recordings are kept, newest first.
enum AudioRetentionCount: Int, CaseIterable, Identifiable {
  case ten = 10
  case thirty = 30
  case fifty = 50
  case hundred = 100
  case unlimited = 0

  var id: Int { rawValue }

  var label: String {
    switch self {
    case .unlimited: return "Unlimited"
    default: return "\(rawValue) recordings"
    }
  }

  /// Maximum number of recordings, or `nil` for no limit.
  var limit: Int? { self == .unlimited ? nil : rawValue }
}

struct AudioRetentionPolicy: Equatable {
  /// Keep at most this many recordings (newest first). `nil` means unlimited.
  var maxCount: Int?
  /// Delete recordings older than this many seconds. `nil` means keep forever.
  var maxAge: TimeInterval?

  /// Matches the historical behaviour: newest 30 recordings, no age limit.
  static let `default` = AudioRetentionPolicy(maxCount: 30, maxAge: nil)
}

@MainActor
final class DebugSessionStore: ObservableObject {
  @Published private(set) var sessions: [TranscriptionDebugSession] = []

  /// Total size of every file in the audio directory, including orphans that
  /// are no longer referenced by `sessions`.
  @Published private(set) var totalAudioBytes: Int64 = 0

  /// Assigning a policy prunes immediately (a no-op when nothing falls outside it).
  var retentionPolicy: AudioRetentionPolicy = .default {
    didSet { applyRetention() }
  }

  private let metadataFileName = "sessions.json"
  private let audioDirectoryName = "audio"

  let rootDirectory: URL

  /// - Parameter rootDirectory: Where `sessions.json` and the `audio/` folder
  ///   live. Defaults to Application Support; tests pass a temporary directory.
  init(rootDirectory: URL? = nil) {
    self.rootDirectory = rootDirectory ?? Self.defaultRootDirectory()
    load()
    refreshDiskUsage()
  }

  // MARK: - Paths

  private static func defaultRootDirectory() -> URL {
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
    prune(now: Date())
    persist()
    refreshDiskUsage()
    return session
  }

  /// Updates an existing session (e.g., when cloud fallback succeeds after a local failure).
  func update(_ session: TranscriptionDebugSession) {
    guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
    sessions[idx] = session
    persist()
    refreshDiskUsage()
  }

  func clear() {
    for session in sessions {
      if let url = audioURL(for: session) {
        try? FileManager.default.removeItem(at: url)
      }
    }
    sessions = []
    persist()
    refreshDiskUsage()
  }

  func delete(_ session: TranscriptionDebugSession) {
    if let url = audioURL(for: session) {
      try? FileManager.default.removeItem(at: url)
    }
    sessions.removeAll { $0.id == session.id }
    persist()
    refreshDiskUsage()
  }

  // MARK: - Retention

  /// Deletes sessions (metadata and audio) that fall outside `retentionPolicy`:
  /// first anything older than `maxAge`, then anything beyond `maxCount`.
  /// Runs at launch, whenever the policy changes, and after each new recording.
  func applyRetention(now: Date = Date()) {
    guard prune(now: now) else { return }
    persist()
    refreshDiskUsage()
  }

  /// Applies the policy in memory and removes the audio of dropped sessions.
  /// Returns `true` if anything was removed. Caller is responsible for persisting.
  @discardableResult
  private func prune(now: Date) -> Bool {
    var kept = sessions
    if let maxAge = retentionPolicy.maxAge {
      let cutoff = now.addingTimeInterval(-maxAge)
      kept = kept.filter { $0.timestamp >= cutoff }
    }
    if let maxCount = retentionPolicy.maxCount, kept.count > maxCount {
      kept = Array(kept.prefix(maxCount))
    }
    guard kept.count != sessions.count else { return false }

    let keptIDs = Set(kept.map(\.id))
    for session in sessions where !keptIDs.contains(session.id) {
      if let url = audioURL(for: session) {
        try? FileManager.default.removeItem(at: url)
      }
    }
    sessions = kept
    return true
  }

  private func refreshDiskUsage() {
    let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
    guard let urls = try? FileManager.default.contentsOfDirectory(
      at: audioDirectory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
    else {
      totalAudioBytes = 0
      return
    }
    var total: Int64 = 0
    for url in urls {
      guard let values = try? url.resourceValues(forKeys: keys),
        values.isRegularFile == true,
        let size = values.fileSize
      else { continue }
      total += Int64(size)
    }
    totalAudioBytes = total
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
