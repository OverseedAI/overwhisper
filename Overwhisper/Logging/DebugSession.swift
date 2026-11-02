import AVFoundation
import Foundation
import Darwin

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
  typealias Schedule = (Date, @escaping @MainActor () -> Void) -> (() -> Void)
  @Published private(set) var sessions: [TranscriptionDebugSession] = []
  @Published private(set) var totalAudioBytes: Int64 = 0
  @Published private(set) var cleanupError: String?
  @Published private(set) var orphanedAudioCount = 0
  private(set) var nextRetentionDate: Date?
  private(set) var metadataUnavailable = false

  var retentionPolicy: AudioRetentionPolicy = .default {
    didSet { applyRetention() }
  }

  let rootDirectory: URL
  private let clock: () -> Date
  private let schedule: Schedule
  private var cancelScheduledCleanup: (() -> Void)?
  private let removeFile: ((URL) throws -> Void)?
  private let writeMetadata: (Data, URL) throws -> Void
  private var orphanFiles: [(name: String, modified: Date)] = []
  private var audioInUse: Set<UUID> = []
  private var metadataURL: URL { rootDirectory.appendingPathComponent("sessions.json") }
  var audioDirectory: URL { rootDirectory.appendingPathComponent("audio") }

  init(
    rootDirectory: URL? = nil,
    clock: @escaping () -> Date = Date.init,
    schedule: Schedule? = nil,
    removeFile: ((URL) throws -> Void)? = nil,
    writeMetadata: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
  ) {
    let root = rootDirectory ?? Self.defaultRootDirectory()
    // Resolve normal OS aliases (e.g. /var -> /private/var), but never resolve
    // the owned directory itself: a symlink at that boundary must be rejected.
    let parent = root.deletingLastPathComponent().path
    if let resolved = realpath(parent, nil) {
      self.rootDirectory = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
        .appendingPathComponent(root.lastPathComponent, isDirectory: true)
      free(resolved)
    } else {
      self.rootDirectory = root
    }
    self.clock = clock
    self.schedule = schedule ?? Self.scheduleTimer
    self.removeFile = removeFile
    self.writeMetadata = writeMetadata
    load()
    refreshDiskUsage()
  }

  deinit { cancelScheduledCleanup?() }

  private static func defaultRootDirectory() -> URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.overseed.overwhisper")
      .appendingPathComponent("DebugSessions")
  }

  private static func scheduleTimer(at date: Date, action: @escaping @MainActor () -> Void) -> (() -> Void) {
    let timer = Timer(timeInterval: max(0.01, date.timeIntervalSinceNow), repeats: false) { _ in
      Task { @MainActor in action() }
    }
    RunLoop.main.add(timer, forMode: .common)
    return { timer.invalidate() }
  }

  /// A descriptor walk rejects symlinks at every component and pins the owned
  /// directory against rename races. unlinkat below cannot recursively delete.
  private func directoryDescriptor(_ url: URL) throws -> Int32 {
    var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard descriptor >= 0 else { throw posixError() }
    do {
      for component in url.path.split(separator: "/") {
        let next = String(component).withCString {
          openat(descriptor, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard next >= 0 else { throw posixError() }
        close(descriptor)
        descriptor = next
      }
      return descriptor
    } catch {
      close(descriptor)
      throw error
    }
  }

  private func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }

  private func validAudioName(_ name: String, id: UUID? = nil) -> Bool {
    guard name.count == 40, name.hasSuffix(".wav"),
          let uuid = UUID(uuidString: String(name.dropLast(4))) else { return false }
    return id == nil || uuid == id
  }

  private func regularFileInfo(_ name: String, descriptor: Int32) throws -> stat? {
    var info = stat()
    let result = name.withCString { fstatat(descriptor, $0, &info, AT_SYMLINK_NOFOLLOW) }
    if result != 0 {
      if errno == ENOENT { return nil }
      throw posixError()
    }
    guard info.st_mode & S_IFMT == S_IFREG else {
      throw NSError(domain: "DebugSessionStore", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Recording is not a regular file."])
    }
    return info
  }

  func audioURL(for session: TranscriptionDebugSession) -> URL? {
    guard let name = session.audioFileName, validAudioName(name, id: session.id),
          let descriptor = try? directoryDescriptor(audioDirectory) else { return nil }
    defer { close(descriptor) }
    guard (try? regularFileInfo(name, descriptor: descriptor)) != nil else { return nil }
    return audioDirectory.appendingPathComponent(name)
  }

  func acquireAudio(for session: TranscriptionDebugSession) -> URL? {
    guard let url = audioURL(for: session) else { return nil }
    audioInUse.insert(session.id)
    return url
  }

  func releaseAudio(for session: TranscriptionDebugSession) {
    audioInUse.remove(session.id)
    retryCleanup()
  }

  private func removeAudio(named name: String, id: UUID? = nil) throws {
    guard validAudioName(name, id: id) else {
      throw NSError(domain: "DebugSessionStore", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Recording filename is invalid."])
    }
    let descriptor: Int32
    do { descriptor = try directoryDescriptor(audioDirectory) }
    catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) { return }
    defer { close(descriptor) }
    guard try regularFileInfo(name, descriptor: descriptor) != nil else { return }
    if let removeFile {
      try removeFile(audioDirectory.appendingPathComponent(name))
    } else if name.withCString({ unlinkat(descriptor, $0, 0) }) != 0, errno != ENOENT {
      throw posixError()
    }
  }

  private func ensureDirectories() throws {
    try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
    let descriptor = try directoryDescriptor(audioDirectory)
    close(descriptor)
  }

  @discardableResult
  func record(
    engine: String, model: String, sourceAudioURL: URL?, recordingDuration: Double,
    transcribedText: String, latencySeconds: Double, language: String?,
    errorMessage: String?, usedCloudFallback: Bool
  ) -> TranscriptionDebugSession {
    let id = UUID()
    var name: String?
    var storageError: String?
    var size: Int64?
    var duration: Double?
    if !metadataUnavailable, let source = sourceAudioURL {
      do {
        try ensureDirectories()
        let destination = audioDirectory.appendingPathComponent("\(id.uuidString).wav")
        try FileManager.default.moveItem(at: source, to: destination)
        name = destination.lastPathComponent
        size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value
        duration = Self.duration(of: destination)
      } catch {
        storageError = "Could not save recording audio. Existing recordings have been preserved."
        AppLogger.app.error("DebugSessionStore: could not store audio: \(error.localizedDescription)")
      }
    }
    let session = TranscriptionDebugSession(
      id: id, timestamp: clock(), engine: engine, model: model, audioFileName: name,
      audioFileSizeBytes: size, audioDurationSeconds: duration,
      recordingDurationSeconds: recordingDuration, transcribedText: transcribedText,
      latencySeconds: latencySeconds, language: language, errorMessage: errorMessage,
      usedCloudFallback: usedCloudFallback)
    // Never overwrite unreadable metadata or guess that its audio is disposable.
    guard !metadataUnavailable else { return session }
    sessions.insert(session, at: 0)
    applyRetention()
    if let storageError, cleanupError == nil { cleanupError = storageError }
    return session
  }

  func update(_ session: TranscriptionDebugSession) {
    guard !metadataUnavailable, let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
    sessions[index] = session
    persist()
    refreshDiskUsage()
    reschedule()
  }

  var clearableRecordingCount: Int { sessions.count + orphanedAudioCount }

  func clear() {
    guard !metadataUnavailable else { return }
    cleanupError = nil
    removeSessions(Set(sessions.map(\.id)))
    removeOrphans(orphanFiles)
    persist()
    refreshDiskUsage()
    reschedule()
  }

  func delete(_ session: TranscriptionDebugSession) {
    guard !metadataUnavailable else { return }
    cleanupError = nil
    removeSessions([session.id])
    persist()
    refreshDiskUsage()
    reschedule()
  }

  private func expiredIDs(for policy: AudioRetentionPolicy, now: Date) -> Set<UUID> {
    var kept = sessions
    if let age = policy.maxAge { kept = kept.filter { $0.timestamp > now.addingTimeInterval(-age) } }
    if let count = policy.maxCount { kept = Array(kept.prefix(max(0, count))) }
    return Set(sessions.map(\.id)).subtracting(kept.map(\.id))
  }

  func deletionCount(for policy: AudioRetentionPolicy) -> Int {
    expiredIDs(for: policy, now: clock()).count + expiredOrphans(for: policy, now: clock()).count
  }

  private func expiredOrphans(for policy: AudioRetentionPolicy, now: Date) -> [(name: String, modified: Date)] {
    guard let age = policy.maxAge else { return [] }
    return orphanFiles.filter { $0.modified <= now.addingTimeInterval(-age) }
  }

  func applyRetention(now: Date? = nil) {
    guard !metadataUnavailable else { return }
    cleanupError = nil
    let now = now ?? clock()
    removeSessions(expiredIDs(for: retentionPolicy, now: now))
    removeOrphans(expiredOrphans(for: retentionPolicy, now: now))
    persist()
    refreshDiskUsage()
    reschedule()
  }

  /// Reconcile after wake/activation, or retry after a recoverable storage error.
  func retryCleanup() {
    if metadataUnavailable { load() }
    refreshDiskUsage()
    applyRetention()
  }

  private func removeSessions(_ ids: Set<UUID>) {
    var removed = Set<UUID>()
    for session in sessions where ids.contains(session.id) {
      guard !audioInUse.contains(session.id) else {
        cleanupError = "A recording is in use. Cleanup will retry when transcription finishes."
        continue
      }
      do {
        if let name = session.audioFileName { try removeAudio(named: name, id: session.id) }
        removed.insert(session.id)
      } catch {
        cleanupError = "Some recordings could not be deleted. They remain tracked; cleanup will retry."
      }
    }
    sessions.removeAll { removed.contains($0.id) }
  }

  private func removeOrphans(_ files: [(name: String, modified: Date)]) {
    for file in files {
      do { try removeAudio(named: file.name) }
      catch { cleanupError = "Some unindexed recordings could not be deleted. Cleanup will retry." }
    }
  }

  private func reschedule() {
    cancelScheduledCleanup?()
    cancelScheduledCleanup = nil
    nextRetentionDate = nil
    guard !metadataUnavailable else { return }
    let now = clock()
    var next: Date?
    if let age = retentionPolicy.maxAge {
      next = (sessions.map(\.timestamp) + orphanFiles.map(\.modified)).min()?.addingTimeInterval(age)
    }
    if cleanupError != nil { next = max(next ?? now, now.addingTimeInterval(60)) }
    guard let next else { return }
    let date = max(next, now.addingTimeInterval(0.01))
    nextRetentionDate = date
    cancelScheduledCleanup = schedule(date) { [weak self] in self?.retryCleanup() }
  }

  private func refreshDiskUsage() {
    orphanFiles = []
    totalAudioBytes = 0
    orphanedAudioCount = 0
    guard let descriptor = try? directoryDescriptor(audioDirectory) else { return }
    defer { close(descriptor) }
    let referenced = Set(sessions.compactMap(\.audioFileName))
    guard let urls = try? FileManager.default.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: nil) else { return }
    for url in urls {
      let name = url.lastPathComponent
      guard let info = try? regularFileInfo(name, descriptor: descriptor) else { continue }
      totalAudioBytes += Int64(info.st_size)
      if validAudioName(name), !referenced.contains(name) {
        orphanFiles.append((name, Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))))
      }
    }
    orphanedAudioCount = orphanFiles.count
  }

  private func load() {
    do {
      if !FileManager.default.fileExists(atPath: metadataURL.path) {
        // A missing index with existing audio is ambiguous; preserve everything.
        let files = (try? FileManager.default.contentsOfDirectory(atPath: audioDirectory.path)) ?? []
        guard files.isEmpty else { throw NSError(domain: "DebugSessionStore", code: 3) }
        sessions = []
      } else {
        let descriptor = try directoryDescriptor(rootDirectory)
        defer { close(descriptor) }
        guard try regularFileInfo("sessions.json", descriptor: descriptor) != nil else {
          throw NSError(domain: "DebugSessionStore", code: 4)
        }
        let data = try Data(contentsOf: metadataURL)
        let decoded = try JSONDecoder.iso8601().decode([TranscriptionDebugSession].self, from: data)
        guard Set(decoded.map(\.id)).count == decoded.count else {
          throw NSError(domain: "DebugSessionStore", code: 5)
        }
        sessions = decoded.sorted { $0.timestamp > $1.timestamp }
      }
      metadataUnavailable = false
      cleanupError = nil
    } catch {
      metadataUnavailable = true
      cleanupError = "Saved history could not be loaded. Existing files are preserved. Restore the history index, then retry."
    }
  }

  @discardableResult
  private func persist() -> Bool {
    guard !metadataUnavailable else { return false }
    do {
      try ensureDirectories()
      if FileManager.default.fileExists(atPath: metadataURL.path) {
        let descriptor = try directoryDescriptor(rootDirectory)
        defer { close(descriptor) }
        _ = try regularFileInfo("sessions.json", descriptor: descriptor)
      }
      try writeMetadata(JSONEncoder.iso8601().encode(sessions), metadataURL)
      return true
    } catch {
      cleanupError = "Could not save history changes. Cleanup will retry; existing metadata is preserved."
      return false
    }
  }

  private static func duration(of url: URL) -> Double? {
    guard let file = try? AVAudioFile(forReading: url) else { return nil }
    let rate = file.processingFormat.sampleRate
    return rate > 0 ? Double(file.length) / rate : nil
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
