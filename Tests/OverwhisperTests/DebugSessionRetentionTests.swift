import XCTest

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
    let store = DebugSessionStore(rootDirectory: root)
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
    // The policy setter uses the wall clock, so seed ages relative to it.
    let seeded = try seed(ages: [60, 2 * 86_400, 400 * 86_400], relativeTo: Date())
    let store = DebugSessionStore(rootDirectory: root)
    XCTAssertEqual(store.sessions.count, 3)

    store.retentionPolicy = AudioRetentionPolicy(maxCount: 30, maxAge: 365 * 86_400)

    XCTAssertEqual(store.sessions.map(\.id), [seeded[0].id, seeded[1].id])
    XCTAssertFalse(audioExists(seeded[2]))

    // A fresh store reading the same directory sees the pruned list.
    let reloaded = DebugSessionStore(rootDirectory: root)
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
}
