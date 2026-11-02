import XCTest
import Combine

@testable import Overwhisper

@MainActor
final class DebugSessionRetentionTests: XCTestCase {
  private var root: URL!
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  override func setUp() {
    super.setUp()
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("DebugSessionRetentionTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(
      at: root.appendingPathComponent("audio"), withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: root)
    root = nil
    super.tearDown()
  }

  // MARK: - Helpers

  /// Writes `sessions.json` plus a 1 KB dummy wav per session, newest first,
  /// and returns the sessions in that order.
  @discardableResult
  private func seed(
    ages: [TimeInterval], relativeTo base: Date? = nil, audio: Bool = true
  ) throws -> [TranscriptionDebugSession] {
    let base = base ?? now
    let sessions = ages.sorted().map { age -> TranscriptionDebugSession in
      let id = UUID()
      return TranscriptionDebugSession(
        id: id,
        timestamp: base.addingTimeInterval(-age),
        engine: "test",
        model: "test",
        audioFileName: audio ? "\(id.uuidString).wav" : nil,
        audioFileSizeBytes: audio ? 1024 : nil,
        audioDurationSeconds: nil,
        recordingDurationSeconds: 1,
        transcribedText: "hello",
        latencySeconds: 0.1,
        language: nil,
        errorMessage: nil,
        usedCloudFallback: false
      )
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(sessions).write(to: root.appendingPathComponent("sessions.json"))
    if audio {
      for session in sessions {
        try writeAudio(named: session.audioFileName!)
      }
    }
    return sessions
  }

  private func writeAudio(named name: String, bytes: Int = 1024) throws {
    try Data(repeating: 0, count: bytes)
      .write(to: root.appendingPathComponent("audio").appendingPathComponent(name))
  }

  private func audioExists(_ session: TranscriptionDebugSession) -> Bool {
    guard let name = session.audioFileName else { return false }
    return FileManager.default.fileExists(
      atPath: root.appendingPathComponent("audio").appendingPathComponent(name).path)
  }

  private func makeStore(_ policy: AudioRetentionPolicy = .default) -> DebugSessionStore {
    let store = DebugSessionStore(rootDirectory: root, clock: { self.now }, schedule: { _, _ in {} })
    store.retentionPolicy = policy
    return store
  }

  // MARK: - Policy mapping

  func testAgeAndCountOptionsMapToPolicyValues() {
    XCTAssertEqual(AudioRetentionAge.oneDay.maxAge, 86_400)
    XCTAssertEqual(AudioRetentionAge.sevenDays.maxAge, 7 * 86_400)
    XCTAssertEqual(AudioRetentionAge.thirtyDays.maxAge, 30 * 86_400)
    XCTAssertEqual(AudioRetentionAge.ninetyDays.maxAge, 90 * 86_400)
    XCTAssertNil(AudioRetentionAge.never.maxAge)

    XCTAssertEqual(AudioRetentionCount.ten.limit, 10)
    XCTAssertEqual(AudioRetentionCount.thirty.limit, 30)
    XCTAssertNil(AudioRetentionCount.unlimited.limit)

    XCTAssertEqual(AudioRetentionPolicy.default, AudioRetentionPolicy(maxCount: 30, maxAge: nil))
  }

  // MARK: - Pruning

  func testDefaultPolicyKeepsNewestThirty() throws {
    let seeded = try seed(ages: (0..<35).map { TimeInterval($0 * 60) })
    let store = makeStore()

    store.applyRetention(now: now)

    XCTAssertEqual(store.sessions.count, 30)
    XCTAssertEqual(store.sessions.map(\.id), seeded.prefix(30).map(\.id))
    for session in seeded.prefix(30) { XCTAssertTrue(audioExists(session)) }
    for session in seeded.suffix(5) { XCTAssertFalse(audioExists(session)) }
  }

  func testAgePolicyDeletesOlderSessionsAndAudio() throws {
    let hour: TimeInterval = 3_600
    let day: TimeInterval = 86_400
    let seeded = try seed(ages: [hour, 2 * day, 10 * day])
    let store = makeStore(AudioRetentionPolicy(maxCount: 30, maxAge: 7 * day))

    store.applyRetention(now: now)

    XCTAssertEqual(store.sessions.map(\.id), [seeded[0].id, seeded[1].id])
    XCTAssertTrue(audioExists(seeded[0]))
    XCTAssertTrue(audioExists(seeded[1]))
    XCTAssertFalse(audioExists(seeded[2]))
  }

  func testNeverAndUnlimitedKeepsEverything() throws {
    let seeded = try seed(ages: (0..<40).map { TimeInterval($0) * 86_400 })
    let store = makeStore(AudioRetentionPolicy(maxCount: nil, maxAge: nil))

    store.applyRetention(now: now)

    XCTAssertEqual(store.sessions.count, 40)
    for session in seeded { XCTAssertTrue(audioExists(session)) }
  }

  func testAgeThenCountAreBothApplied() throws {
    // 20 sessions younger than 7 days, 20 older.
    let young = (0..<20).map { TimeInterval($0) * 3_600 }
    let old = (0..<20).map { 8 * 86_400 + TimeInterval($0) * 3_600 }
    let seeded = try seed(ages: young + old)
    let store = makeStore(AudioRetentionPolicy(maxCount: 10, maxAge: 7 * 86_400))

    store.applyRetention(now: now)

    XCTAssertEqual(store.sessions.count, 10)
    XCTAssertEqual(store.sessions.map(\.id), seeded.prefix(10).map(\.id))
    for session in seeded.dropFirst(10) { XCTAssertFalse(audioExists(session)) }
  }

  func testSettingPolicyPrunesImmediatelyAndPersists() throws {
    // Policy assignment and explicit pruning share the same injected clock.
    let seeded = try seed(ages: [60, TimeInterval(2 * 86_400), TimeInterval(400 * 86_400)], relativeTo: now)
    let store = DebugSessionStore(rootDirectory: root, clock: { self.now }, schedule: { _, _ in {} })
    XCTAssertEqual(store.sessions.count, 3)

    store.retentionPolicy = AudioRetentionPolicy(maxCount: 30, maxAge: 365 * 86_400)

    XCTAssertEqual(store.sessions.map(\.id), [seeded[0].id, seeded[1].id])
    XCTAssertFalse(audioExists(seeded[2]))

    // A fresh store reading the same directory sees the pruned list.
    let reloaded = DebugSessionStore(rootDirectory: root, clock: { self.now }, schedule: { _, _ in {} })
    XCTAssertEqual(reloaded.sessions.map(\.id), [seeded[0].id, seeded[1].id])
  }

  func testRecordAppliesCountCap() throws {
    try seed(ages: (0..<30).map { TimeInterval($0 * 60) }, audio: false)
    let store = makeStore(AudioRetentionPolicy(maxCount: 30, maxAge: nil))
    XCTAssertEqual(store.sessions.count, 30)

    let recorded = store.record(
      engine: "test", model: "test", sourceAudioURL: nil, recordingDuration: 1,
      transcribedText: "new", latencySeconds: 0.1, language: nil,
      errorMessage: nil, usedCloudFallback: false)

    XCTAssertEqual(store.sessions.count, 30)
    XCTAssertEqual(store.sessions.first?.id, recorded.id)
  }

  func testRecordKeepsAudioStorageFailureVisibleAfterRetention() throws {
    try seed(ages: [], audio: false)
    let store = makeStore()

    let recorded = store.record(
      engine: "test", model: "test", sourceAudioURL: root.appendingPathComponent("missing.wav"),
      recordingDuration: 1, transcribedText: "new", latencySeconds: 0.1, language: nil,
      errorMessage: nil, usedCloudFallback: false)

    XCTAssertNil(recorded.audioFileName)
    XCTAssertEqual(store.cleanupError, "Could not save recording audio. Existing recordings have been preserved.")
    let reloaded = makeStore()
    XCTAssertEqual(reloaded.sessions.map(\.id), [recorded.id])
  }

  func testRecordPreservesRetentionErrorWhenAudioStorageAlsoFails() throws {
    try seed(ages: [], audio: false)
    let store = DebugSessionStore(
      rootDirectory: root, clock: { self.now }, schedule: { _, _ in {} },
      writeMetadata: { _, _ in throw CocoaError(.fileWriteNoPermission) })

    _ = store.record(
      engine: "test", model: "test", sourceAudioURL: root.appendingPathComponent("missing.wav"),
      recordingDuration: 1, transcribedText: "new", latencySeconds: 0.1, language: nil,
      errorMessage: nil, usedCloudFallback: false)

    XCTAssertEqual(store.cleanupError, "Could not save history changes. Cleanup will retry; existing metadata is preserved.")
  }

  // MARK: - Disk usage

  func testTotalAudioBytesTracksFilesOnDisk() throws {
    let seeded = try seed(ages: [0, 60])
    try writeAudio(named: "orphan.wav", bytes: 512)
    let store = makeStore(AudioRetentionPolicy(maxCount: nil, maxAge: nil))

    XCTAssertEqual(store.totalAudioBytes, 2 * 1024 + 512)

    store.delete(seeded[0])
    XCTAssertEqual(store.totalAudioBytes, 1024 + 512)

    store.clear()
    XCTAssertEqual(store.totalAudioBytes, 512)
  }

  func testClearDoesNotFollowMetadataOutsideAudioDirectory() throws {
    try seed(ages: [0])
    let metadataURL = root.appendingPathComponent("sessions.json")
    var metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as? [[String: Any]])
    metadata[0]["audioFileName"] = "../victim.txt"
    try JSONSerialization.data(withJSONObject: metadata).write(to: metadataURL)
    let victim = root.appendingPathComponent("victim.txt")
    try Data("must survive".utf8).write(to: victim)

    let store = makeStore(AudioRetentionPolicy(maxCount: nil, maxAge: nil))
    store.clear()

    XCTAssertTrue(FileManager.default.fileExists(atPath: victim.path))
    XCTAssertEqual(store.sessions.count, 1, "An unsafe deletion must remain tracked")
  }

  func testClearDoesNotRecursivelyDeleteDirectoryMasqueradingAsRecording() throws {
    let seeded = try seed(ages: [0], audio: false)
    let metadataURL = root.appendingPathComponent("sessions.json")
    var metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as? [[String: Any]])
    let name = "\(seeded[0].id.uuidString).wav"
    metadata[0]["audioFileName"] = name
    try JSONSerialization.data(withJSONObject: metadata).write(to: metadataURL)
    let directory = root.appendingPathComponent("audio").appendingPathComponent(name)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    try Data("must survive".utf8).write(to: directory.appendingPathComponent("victim.txt"))

    let store = makeStore(AudioRetentionPolicy(maxCount: nil, maxAge: nil))
    store.clear()

    XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    XCTAssertEqual(store.sessions.count, 1)
  }

  func testDeletionFailureRemainsTrackedAcrossRestartAndRetries() throws {
    let seeded = try seed(ages: [TimeInterval(2 * 86_400)])
    var failRemoval = true
    let store = DebugSessionStore(rootDirectory: root, clock: { self.now }, schedule: { _, _ in {} }, removeFile: { url in
      if failRemoval { throw CocoaError(.fileWriteNoPermission) }
      try FileManager.default.removeItem(at: url)
    })
    store.retentionPolicy = AudioRetentionPolicy(maxCount: nil, maxAge: 86_400)
    XCTAssertEqual(store.sessions.map(\.id), seeded.map(\.id))
    XCTAssertTrue(audioExists(seeded[0]))
    XCTAssertNotNil(store.cleanupError)
    XCTAssertEqual(makeStore().sessions.count, 1)

    failRemoval = false
    store.retryCleanup()
    XCTAssertTrue(store.sessions.isEmpty)
    XCTAssertFalse(audioExists(seeded[0]))
    XCTAssertNil(store.cleanupError)
  }

  func testMetadataWriteFailureIsVisibleAndRetryable() throws {
    let seeded = try seed(ages: [0])
    var failWrite = true
    let store = DebugSessionStore(rootDirectory: root, clock: { self.now }, schedule: { _, _ in {} }, writeMetadata: { data, url in
      if failWrite { throw CocoaError(.fileWriteNoPermission) }
      try data.write(to: url, options: .atomic)
    })
    store.clear()
    XCTAssertNotNil(store.cleanupError)
    XCTAssertFalse(audioExists(seeded[0]))
    failWrite = false
    store.retryCleanup()
    XCTAssertNil(store.cleanupError)
    XCTAssertTrue(makeStore().sessions.isEmpty)
  }

  func testScheduledExpirationRunsWithoutRecordingOrChangingSettings() throws {
    let seeded = try seed(ages: [60, 120])
    var instant = now
    var scheduled: (@MainActor () -> Void)?
    var deadline: Date?
    let store = DebugSessionStore(rootDirectory: root, clock: { instant }, schedule: { date, action in
      deadline = date
      scheduled = action
      return {}
    })
    store.retentionPolicy = AudioRetentionPolicy(maxCount: nil, maxAge: 86_400)
    XCTAssertEqual(deadline, seeded[1].timestamp.addingTimeInterval(86_400))
    instant = try XCTUnwrap(deadline)
    scheduled?()
    XCTAssertEqual(store.sessions.map(\.id), [seeded[0].id])
    XCTAssertFalse(audioExists(seeded[1]))
    XCTAssertEqual(deadline, seeded[0].timestamp.addingTimeInterval(86_400))

    store.retentionPolicy = AudioRetentionPolicy(maxCount: nil, maxAge: nil)
    XCTAssertNil(store.nextRetentionDate)
  }

  func testWakeReconciliationExpiresAudioAfterClockJump() throws {
    let seeded = try seed(ages: [60])
    var instant = now
    let store = DebugSessionStore(rootDirectory: root, clock: { instant }, schedule: { _, _ in {} })
    store.retentionPolicy = AudioRetentionPolicy(maxCount: nil, maxAge: 86_400)
    instant = instant.addingTimeInterval(2 * 86_400)
    store.retryCleanup()
    XCTAssertTrue(store.sessions.isEmpty)
    XCTAssertFalse(audioExists(seeded[0]))
  }

  func testCorruptMetadataIsPreservedAndNeverTriggersOrphanSweep() throws {
    let seeded = try seed(ages: [TimeInterval(10 * 86_400)])
    let metadataURL = root.appendingPathComponent("sessions.json")
    let corruptData = Data("broken metadata".utf8)
    try corruptData.write(to: metadataURL)
    let store = makeStore(AudioRetentionPolicy(maxCount: 0, maxAge: 0))
    store.clear()
    store.retryCleanup()
    _ = store.record(engine: "test", model: "test", sourceAudioURL: nil, recordingDuration: 1,
                     transcribedText: "new", latencySeconds: 0, language: nil, errorMessage: nil, usedCloudFallback: false)
    XCTAssertTrue(store.metadataUnavailable)
    XCTAssertNotNil(store.cleanupError)
    XCTAssertEqual(try Data(contentsOf: metadataURL), corruptData)
    XCTAssertTrue(audioExists(seeded[0]))
  }

  func testValidUnindexedAudioExpiresButUnknownFilesRemain() throws {
    try seed(ages: [])
    let orphanName = "\(UUID().uuidString).wav"
    try writeAudio(named: orphanName)
    try writeAudio(named: "do-not-touch.txt")
    let orphan = root.appendingPathComponent("audio").appendingPathComponent(orphanName)
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-2 * 86_400)], ofItemAtPath: orphan.path)
    let store = makeStore(AudioRetentionPolicy(maxCount: nil, maxAge: 86_400))
    XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    XCTAssertEqual(store.orphanedAudioCount, 0)
    XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("audio/do-not-touch.txt").path))
  }

  func testFileAndDirectorySymlinksCannotDeleteTheirTargets() throws {
    let seeded = try seed(ages: [0])
    let target = root.appendingPathComponent("victim.txt")
    try Data("must survive".utf8).write(to: target)
    let audio = root.appendingPathComponent("audio")
    let file = audio.appendingPathComponent(try XCTUnwrap(seeded[0].audioFileName))
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
    let store = makeStore(AudioRetentionPolicy(maxCount: nil, maxAge: nil))
    XCTAssertNil(store.audioURL(for: seeded[0]))
    store.clear()
    XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    XCTAssertEqual(store.sessions.count, 1)

    let moved = root.appendingPathComponent("real-audio")
    try FileManager.default.moveItem(at: audio, to: moved)
    try FileManager.default.createSymbolicLink(at: audio, withDestinationURL: moved)
    store.clear()
    XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    XCTAssertEqual(store.sessions.count, 1)
  }

  func testResetPreservesRetentionSettingsAndAllRecordings() throws {
    let seeded = try seed(ages: (0..<40).map { TimeInterval($0) })
    let suite = "RetentionTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(0, forKey: "audioRetentionMaxCount")
    defaults.set("never", forKey: "audioRetentionAge")
    let store = DebugSessionStore(rootDirectory: root, clock: { self.now }, schedule: { _, _ in {} })
    let state = AppState(defaults: defaults, debugSessionStore: store, loadAPIKey: { nil }, updateLoginItem: { _ in })
    XCTAssertNil(store.retentionPolicy.maxCount, "Saved Unlimited policy must be installed before lifecycle callbacks")
    let binding = state.$audioRetentionPolicy.sink { store.retentionPolicy = $0 }
    defer { binding.cancel() }
    state.resetToDefaults()
    XCTAssertNil(state.audioRetentionPolicy.maxCount)
    XCTAssertNil(state.audioRetentionPolicy.maxAge)
    XCTAssertEqual(defaults.integer(forKey: "audioRetentionMaxCount"), 0)
    XCTAssertEqual(store.sessions.count, 40)
    for session in seeded { XCTAssertTrue(audioExists(session)) }
  }

  func testMissingDefaultsUseThirtyAndAtomicPolicyUpdatesPublishOnce() throws {
    try seed(ages: [])
    let suite = "RetentionTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = DebugSessionStore(rootDirectory: root, clock: { self.now }, schedule: { _, _ in {} })
    let state = AppState(defaults: defaults, debugSessionStore: store, loadAPIKey: { nil }, updateLoginItem: { _ in })
    XCTAssertEqual(state.audioRetentionMaxCount, .thirty)
    var emitted: [AudioRetentionPolicy] = []
    let binding = state.$audioRetentionPolicy.dropFirst().sink { emitted.append($0) }
    defer { binding.cancel() }
    let policy = AudioRetentionPolicy(maxCount: 100, maxAge: 7 * 86_400)
    state.audioRetentionPolicy = policy
    XCTAssertEqual(emitted, [policy])
    XCTAssertEqual(defaults.integer(forKey: "audioRetentionMaxCount"), 100)
    XCTAssertEqual(defaults.string(forKey: "audioRetentionAge"), "7d")
  }

  func testDeletionPreviewDoesNotMutateHistory() throws {
    let seeded = try seed(ages: (0..<40).map { TimeInterval($0) })
    let store = makeStore(AudioRetentionPolicy(maxCount: nil, maxAge: nil))
    XCTAssertEqual(store.deletionCount(for: .default), 10)
    XCTAssertEqual(store.sessions.count, 40)
    for session in seeded { XCTAssertTrue(audioExists(session)) }
  }

  func testRetentionDefersDeletionUntilActiveTranscriptionReleasesAudio() throws {
    let seeded = try seed(ages: [TimeInterval(2 * 86_400)])
    let store = makeStore(AudioRetentionPolicy(maxCount: nil, maxAge: nil))
    let lease = try XCTUnwrap(store.acquireAudio(for: seeded[0]))
    store.retentionPolicy = AudioRetentionPolicy(maxCount: nil, maxAge: 86_400)
    XCTAssertTrue(audioExists(seeded[0]))
    XCTAssertEqual(store.sessions.count, 1)
    store.releaseAudio(lease)
    XCTAssertFalse(audioExists(seeded[0]))
    XCTAssertTrue(store.sessions.isEmpty)
  }

  func testFailedOrEmptyRetryPreservesSuccessfulResultAcrossRestart() throws {
    let original = try seed(ages: [0])[0]
    let store = makeStore()
    for error in ["Cancelled by user", "Engine failed", nil] {
      let attempt = original.withResult(
        engine: "replacement", model: "replacement", transcribedText: "",
        latencySeconds: 2, language: "en", errorMessage: error, usedCloudFallback: false)
      XCTAssertEqual(store.updateRetry(attempt), original)
      XCTAssertEqual(store.sessions, [original])
    }
    XCTAssertEqual(makeStore().sessions, [original])
  }

  func testSuccessfulRetryReplacesTextWithoutMovingAudio() throws {
    let original = try seed(ages: [0])[0]
    let store = makeStore()
    let attempt = original.withResult(
      engine: "replacement", model: "replacement", transcribedText: "new text",
      latencySeconds: 2, language: "en", errorMessage: nil, usedCloudFallback: true)
    XCTAssertEqual(store.updateRetry(attempt), attempt)
    XCTAssertEqual(makeStore().sessions, [attempt])
    XCTAssertTrue(audioExists(original))
  }

  func testClearAndDeleteCannotRemoveAudioUntilAllReadersReleaseIt() throws {
    let original = try seed(ages: [0])[0]
    let store = makeStore()
    let first = try XCTUnwrap(store.acquireAudio(for: original))
    let second = try XCTUnwrap(store.acquireAudio(for: original))
    store.releaseAudio(first)
    store.releaseAudio(first) // Releasing twice must not retire another reader.
    store.clear()
    store.delete(original)
    XCTAssertTrue(audioExists(original))
    XCTAssertEqual(store.sessions.count, 1)
    store.releaseAudio(second)
    store.clear()
    XCTAssertFalse(audioExists(original))
  }

  func testRetrySnapshotDoesNotFollowReplacedSourceAndIsRemovedOnRelease() throws {
    let original = try seed(ages: [0])[0]
    let store = makeStore()
    let lease = try XCTUnwrap(store.acquireAudio(for: original))
    defer { store.releaseAudio(lease) }
    let expected = try Data(contentsOf: lease.url)
    let source = try XCTUnwrap(store.audioURL(for: original))
    let other = root.appendingPathComponent("other.wav")
    try Data("different recording".utf8).write(to: other)
    try FileManager.default.removeItem(at: source)
    try FileManager.default.createSymbolicLink(at: source, withDestinationURL: other)
    XCTAssertNil(store.acquireAudio(for: original))
    XCTAssertEqual(try Data(contentsOf: lease.url), expected)
    store.releaseAudio(lease)
    XCTAssertFalse(FileManager.default.fileExists(atPath: lease.url.path))
    XCTAssertEqual(try Data(contentsOf: other), Data("different recording".utf8))
  }

  func testRetryRejectsHardLinkedFiles() throws {
    let original = try seed(ages: [0])[0]
    let store = makeStore()
    let source = try XCTUnwrap(store.audioURL(for: original))
    try FileManager.default.linkItem(at: source, to: root.appendingPathComponent("alias.wav"))
    XCTAssertNil(store.acquireAudio(for: original))
  }

}
