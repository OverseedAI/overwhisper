import XCTest
@testable import Overwhisper

@MainActor
final class WhisperModelStateTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var root: URL!

    override func setUpWithError() throws {
        suite = "WhisperModelStateTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    private func makeState() -> AppState {
        AppState(defaults: defaults,
                 debugSessionStore: DebugSessionStore(rootDirectory: root, schedule: { _, _ in {} }),
                 loadAPIKey: { nil }, updateLoginItem: { _ in })
    }

    func testUpgradeKeepsLegacyModelAndExplicitLanguage() {
        defaults.set("medium.en", forKey: "whisperModel")
        defaults.set("auto", forKey: "language")
        let state = makeState()
        XCTAssertEqual(state.whisperModel.rawValue, "medium.en")
        XCTAssertEqual(state.whisperModelTier, .medium)
        XCTAssertEqual(state.language, "auto")
        XCTAssertFalse(state.isDownloadingModel)
    }

    func testMalformedStoredModelFallsBackToSmall() {
        defaults.set("openai_whisper-../bad", forKey: "whisperModel")
        let state = makeState()
        XCTAssertEqual(state.whisperModel, .smallEn)
        XCTAssertEqual(state.language, "en")
    }

    func testLanguageChangesSwitchOnlyToDownloadedVariant() {
        let state = makeState()
        state.downloadedModels = ["openai_whisper-small.en"]
        state.language = "ja"
        XCTAssertEqual(state.whisperModel, .smallEn)
        XCTAssertFalse(state.isDownloadingModel)
        state.downloadedModels.insert("openai_whisper-small")
        state.language = "en"
        state.language = "ja"
        XCTAssertEqual(state.whisperModel, .small)
        XCTAssertEqual(defaults.string(forKey: "language"), "ja")
        XCTAssertEqual(defaults.string(forKey: "whisperModel"), "openai_whisper-small")
        XCTAssertFalse(state.isDownloadingModel)
    }

    func testExactChoiceStaysPinnedAfterLanguageChangeAndRelaunch() {
        let state = makeState()
        state.downloadedModels = ["openai_whisper-small.en", "openai_whisper-small"]
        state.selectExactWhisperModel(.smallEn)
        state.language = "ja"
        XCTAssertEqual(state.whisperModel, .smallEn)
        XCTAssertNil(state.whisperModelTier)
        let restored = makeState()
        XCTAssertNil(restored.whisperModelTier)
        XCTAssertEqual(restored.whisperModel, .smallEn)
        XCTAssertEqual(restored.language, "ja")
    }

    func testTranslationUsesMultilingualVariantWhenDownloaded() {
        let state = makeState()
        state.downloadedModels = ["openai_whisper-small.en", "openai_whisper-small"]
        state.translateToEnglish = true
        XCTAssertEqual(state.whisperModel, .small)
        state.translateToEnglish = false
        XCTAssertEqual(state.whisperModel, .smallEn)
    }

    func testEngineAndParakeetSwitchesNormalizeUnsupportedLanguage() {
        let state = makeState()
        state.language = "hi"
        state.transcriptionEngine = .parakeet
        XCTAssertEqual(state.language, "auto")
        state.language = "ja"
        state.parakeetModel = .v2English
        XCTAssertEqual(state.language, "en")
        state.parakeetModel = .v3Multilingual
        state.language = "fr"
        state.transcriptionEngine = .whisperKit
        XCTAssertEqual(state.language, "fr")
    }
}
