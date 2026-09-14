import XCTest
import WhisperKit
@testable import Overwhisper

final class WhisperLanguagesTests: XCTestCase {

    /// Regression: the picker listed 11 languages, so Bengali, Hindi and Urdu speakers could only
    /// reach their language via Auto-detect — with no way to pin it when detection misfired.
    func testWidelySpokenLanguagesArePinnable() {
        let codes = Set(WhisperLanguages.all.map(\.0))
        for code in ["bn", "hi", "ur", "ta", "te", "mr", "vi", "th", "id"] {
            XCTAssertTrue(codes.contains(code), "\(code) must be selectable, not Auto-detect only")
        }
    }

    /// Every offered code must be one Whisper actually understands, or selecting it silently
    /// produces wrong output rather than an error.
    func testEveryOfferedCodeIsRecognizedByWhisper() {
        let known = Set(Constants.languages.values)
        for (code, name) in WhisperLanguages.all where code != "auto" {
            XCTAssertTrue(known.contains(code), "\(name) (\(code)) is not a Whisper language code")
        }
    }

    func testAutoDetectIsFirstAndEnglishSecond() {
        XCTAssertEqual(WhisperLanguages.all.first?.0, "auto")
        XCTAssertEqual(WhisperLanguages.all.dropFirst().first?.0, "en")
    }

    func testNoDuplicateCodesOrNames() {
        let codes = WhisperLanguages.all.map(\.0)
        let names = WhisperLanguages.all.map(\.1)
        XCTAssertEqual(Set(codes).count, codes.count, "duplicate language code")
        XCTAssertEqual(Set(names).count, names.count, "duplicate language name")
    }
}
