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

    func testUltraSelectionAndDownloadsSurviveRelaunch() {
        let state = makeState()
        state.transcriptionEngine = .parakeet
        state.parakeetModel = .ultra
        state.language = "fr"
        state.parakeetDownloadedModels = [ParakeetModelType.ultra.rawValue, ParakeetModelType.v3Multilingual.rawValue]

        let restored = makeState()
        XCTAssertEqual(restored.transcriptionEngine, .parakeet)
        XCTAssertEqual(restored.parakeetModel, .ultra)
        XCTAssertEqual(restored.language, "fr")
        XCTAssertEqual(restored.parakeetDownloadedModels, state.parakeetDownloadedModels)
        XCTAssertFalse(restored.isDownloadingModel)
    }

    func testAddingUltraPreservesExistingV3Selection() {
        defaults.set(TranscriptionEngineType.parakeet.rawValue, forKey: "transcriptionEngine")
        defaults.set(ParakeetModelType.v3Multilingual.rawValue, forKey: "parakeetModel")
        defaults.set([ParakeetModelType.v3Multilingual.rawValue], forKey: "parakeetDownloadedModels")
        let state = makeState()
        XCTAssertEqual(state.parakeetModel, .v3Multilingual)
        XCTAssertEqual(state.parakeetDownloadedModels, [ParakeetModelType.v3Multilingual.rawValue])
        XCTAssertFalse(state.isDownloadingModel)
    }

    func testSwitchingBetweenUltraAndEnglishOnlyNormalizesLanguage() {
        let state = makeState()
        state.transcriptionEngine = .parakeet
        state.parakeetModel = .ultra
        state.language = "fr"
        XCTAssertEqual(state.language, "fr")
        state.parakeetModel = .v2English
        XCTAssertEqual(state.language, "en")
        state.transcriptionEngine = .whisperKit
        state.language = "ko"
        state.parakeetModel = .ultra
        state.transcriptionEngine = .parakeet
        XCTAssertEqual(state.language, "auto")
    }


    func testDownloadProgressIgnoresLateCallbacksAndStaysMonotonic() {
        let state = makeState()
        let modelID = ParakeetModelType.ultra.rawValue
        state.isDownloadingModel = true
        state.currentlyDownloadingModel = modelID
        state.updateModelDownloadProgress(0.6, for: modelID)
        XCTAssertEqual(state.modelDownloadProgress, 0.6)
        state.updateModelDownloadProgress(0.1, for: modelID) // SDK starts another preparation phase.
        state.updateModelDownloadProgress(.nan, for: modelID)
        state.updateModelDownloadProgress(0.9, for: ParakeetModelType.v3Multilingual.rawValue)
        XCTAssertEqual(state.modelDownloadProgress, 0.6)
        state.updateModelDownloadProgress(1.1, for: modelID)
        XCTAssertEqual(state.modelDownloadProgress, 1)
        state.isDownloadingModel = false
        state.currentlyDownloadingModel = nil
        state.modelDownloadProgress = 0
        state.updateModelDownloadProgress(0.9, for: modelID)
        XCTAssertEqual(state.modelDownloadProgress, 0)
    }


    func testComponentCompletionStaysInPreparationUntilOuterOperationFinishes() {
        let state = makeState()
        let modelID = ParakeetModelType.ultra.rawValue
        state.isDownloadingModel = true
        state.currentlyDownloadingModel = modelID
        state.updateModelDownloadProgress(0.4, for: modelID)
        XCTAssertFalse(state.isPreparingModel)
        state.updateModelDownloadProgress(1, for: modelID, isPreparing: true)
        XCTAssertTrue(state.isPreparingModel)
        state.updateModelDownloadProgress(0, for: modelID) // Next component starts.
        XCTAssertTrue(state.isPreparingModel)
        XCTAssertTrue(state.isDownloadingModel)
        state.isDownloadingModel = false // Outer operation succeeds or fails.
        XCTAssertFalse(state.isPreparingModel)
        state.updateModelDownloadProgress(1, for: modelID, isPreparing: true)
        XCTAssertFalse(state.isPreparingModel)
        state.isDownloadingModel = true
        state.currentlyDownloadingModel = ParakeetModelType.v3Multilingual.rawValue
        state.updateModelDownloadProgress(1, for: modelID, isPreparing: true)
        XCTAssertFalse(state.isPreparingModel)
    }

}
