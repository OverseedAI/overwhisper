import XCTest
import WhisperKit
@testable import Overwhisper

/// Opt-in hardware smoke test. Models and synthetic WAV fixtures must already exist in an
/// isolated directory. Normal CI never downloads weights or accesses personal recordings.
final class NativeWhisperModelTests: XCTestCase {
    func testPrepareMissingModelsForOptInSmokeRun() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["OVERWHISPER_NATIVE_TEST_ROOT"],
              ProcessInfo.processInfo.environment["OVERWHISPER_NATIVE_DOWNLOAD_FIXTURES"] == "1" else {
            throw XCTSkip("Model preparation requires an explicit opt-in and isolated destination")
        }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        for model in WhisperModelSelectionPolicy.curatedModels {
            let folder = root.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(model.variantName)")
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent("AudioEncoder.mlmodelc").path) { continue }
            print("NATIVE_DOWNLOAD \(model.variantName)")
            let downloaded = try await WhisperKit.download(variant: model.variantName, downloadBase: root, token: "")
            XCTAssertEqual(downloaded.lastPathComponent, model.variantName)
        }
    }

    func testCuratedModelsLoadAndTranscribeSyntheticSpeech() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["OVERWHISPER_NATIVE_TEST_ROOT"] else {
            throw XCTSkip("Set OVERWHISPER_NATIVE_TEST_ROOT to an isolated model/audio fixture directory")
        }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let modelRoot = root.appendingPathComponent("models/argmaxinc/whisperkit-coreml")
        for model in WhisperModelSelectionPolicy.curatedModels {
            let started = Date()
            let kit = try await WhisperKit(
                model: model.variantName,
                downloadBase: root,
                modelFolder: modelRoot.appendingPathComponent(model.variantName).path,
                tokenizerFolder: root,
                computeOptions: ModelComputeOptions(audioEncoderCompute: .cpuAndNeuralEngine,
                                                    textDecoderCompute: .cpuAndNeuralEngine),
                verbose: false, logLevel: .error, prewarm: true, load: true, download: false
            )
            let english = try await decode(kit, audio: root.appendingPathComponent("english.wav"), language: "en")
            XCTAssertTrue(english.lowercased().contains("quick brown fox"), "\(model.variantName): \(english)")
            XCTAssertTrue(english.lowercased().contains("speech recognition"), "\(model.variantName): \(english)")
            print("NATIVE_MODEL \(model.variantName) EN: \(english)")
            if !model.isEnglishOnly {
                let japaneseURL = root.appendingPathComponent("japanese.wav")
                let japanese = try await decode(kit, audio: japaneseURL, language: "ja")
                XCTAssertTrue(japanese.contains("天気"), "\(model.variantName): \(japanese)")
                XCTAssertTrue(japanese.contains("図書館"), "\(model.variantName): \(japanese)")
                print("NATIVE_MODEL \(model.variantName) JA: \(japanese)")
                let translated = try await decode(kit, audio: japaneseURL, language: "ja", translate: true)
                XCTAssertTrue(translated.lowercased().contains("library"), "\(model.variantName): \(translated)")
                print("NATIVE_MODEL \(model.variantName) JA->EN: \(translated)")
                if model == .small {
                    let detected = try await kit.detectLanguage(audioPath: japaneseURL.path)
                    XCTAssertEqual(detected.language, "ja")
                }
            }
            print("NATIVE_MODEL \(model.variantName) complete in \(Date().timeIntervalSince(started))s")
            await kit.unloadModels()
        }
    }

    private func decode(_ kit: WhisperKit, audio: URL, language: String, translate: Bool = false) async throws -> String {
        // Match the production engine's decoding behavior, without logging personal audio.
        let options = DecodingOptions(verbose: false, task: translate ? .translate : .transcribe,
                                      language: language, temperature: 0, temperatureFallbackCount: 5,
                                      sampleLength: 224, usePrefillPrompt: true, usePrefillCache: true,
                                      skipSpecialTokens: true, withoutTimestamps: true, clipTimestamps: [])
        return try await kit.transcribe(audioPath: audio.path, decodeOptions: options)
            .map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
