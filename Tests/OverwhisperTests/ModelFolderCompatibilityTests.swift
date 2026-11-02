import XCTest
@testable import Overwhisper

final class ModelFolderCompatibilityTests: XCTestCase {
    func testPreviouslyAcceptedBareFoldersMatchQualifiedPreferences() {
        for model in WhisperModel.legacyModels {
            XCTAssertTrue(ModelManager.isModelVariantFolder(model.rawValue))
            XCTAssertTrue(ModelManager.folderName(model.rawValue, matches: model.variantName))
            XCTAssertTrue(ModelManager.folderName(model.variantName, matches: model.rawValue))
        }
    }

    func testBareCompatibilityDoesNotConflateDistinctLargeVariants() {
        XCTAssertFalse(ModelManager.folderName("large-v3", matches: "openai_whisper-large-v3-v20240930"))
        XCTAssertFalse(ModelManager.folderName("large-v3", matches: "openai_whisper-large-v3_947MB"))
        XCTAssertFalse(ModelManager.folderName("large-v3_turbo", matches: "openai_whisper-large-v3"))
        XCTAssertFalse(ModelManager.isModelVariantFolder("small.en-backup"))
        XCTAssertFalse(ModelManager.folderName("small.en-backup", matches: "openai_whisper-small.en"))
    }
}
