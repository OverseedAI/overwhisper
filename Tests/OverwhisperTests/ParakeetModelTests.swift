import FluidAudio
import XCTest
@testable import Overwhisper

final class ParakeetModelTests: XCTestCase {
    func testEachSelectionRoutesToItsOwnSDKModelAndCache() {
        let expected: [(ParakeetModelType, AsrModelVersion, String)] = [
            (.v2English, .v2, "parakeet-tdt-0.6b-v2"),
            (.v3Multilingual, .v3, "parakeet-tdt-0.6b-v3"),
            (.ultra, .ultra, "parakeet-ultra")
        ]
        XCTAssertEqual(ParakeetModelType.allCases.count, expected.count)
        for (model, version, folder) in expected {
            XCTAssertEqual(model.asrModelVersion, version)
            XCTAssertEqual(model.cacheDirectoryName, folder)
            // Deleting a model in Settings must target the directory the SDK downloads to.
            XCTAssertEqual(model.cacheURL, AsrModels.defaultCacheDirectory(for: version))
            XCTAssertEqual(model.cacheURL?.lastPathComponent, folder)
        }
        XCTAssertEqual(Set(ParakeetModelType.allCases.compactMap(\.cacheURL)).count, expected.count)
    }

    func testUltraSupportsV3LanguagesAndRejectsUnsupportedLanguages() {
        let v3 = TranscriptionLanguagePolicy.choices(engine: .parakeet, parakeet: .v3Multilingual).map(\.0)
        let ultra = TranscriptionLanguagePolicy.choices(engine: .parakeet, parakeet: .ultra).map(\.0)
        XCTAssertEqual(ultra, v3)
        XCTAssertEqual(ultra.count, 26) // Auto-detect plus 25 languages.
        XCTAssertTrue(ultra.contains("fr"))
        XCTAssertFalse(ultra.contains("ko"))
    }
}

/// Opt-in hardware test. Requires pre-downloaded Ultra models and synthetic speech in
/// an isolated directory; normal CI does not download weights or read personal audio.
final class NativeParakeetModelTests: XCTestCase {
    func testUltraLoadsAndTranscribesSyntheticSpeech() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["OVERWHISPER_PARAKEET_TEST_ROOT"] else {
            throw XCTSkip("Set OVERWHISPER_PARAKEET_TEST_ROOT to an isolated model/audio fixture directory")
        }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let model = ParakeetModelType.ultra
        let modelDirectory = root.appendingPathComponent("models/\(model.cacheDirectoryName)")
        guard AsrModels.modelsExist(at: modelDirectory, version: model.asrModelVersion) else {
            XCTFail("Pre-download the complete Ultra model into \(modelDirectory.path)")
            return
        }
        let models = try await AsrModels.load(from: modelDirectory, version: model.asrModelVersion)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(
            root.appendingPathComponent("english.wav"), decoderState: &state, language: .english
        )
        let text = result.text.lowercased()
        XCTAssertTrue(text.contains("quick brown fox"), result.text)
        XCTAssertTrue(text.contains("speech recognition"), result.text)
    }
}
