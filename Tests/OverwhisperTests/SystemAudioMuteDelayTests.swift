import XCTest
@testable import Overwhisper

final class SystemAudioMuteDelayTests: XCTestCase {
    func testNoChimeMutesImmediately() {
        XCTAssertEqual(SystemAudioManager.muteDelay(afterChimeOf: 0), 0)
    }

    func testShortChimeWaitsForItsFullDuration() {
        XCTAssertEqual(SystemAudioManager.muteDelay(afterChimeOf: 0.3), 0.3)
    }

    func testLongChimeFileDoesNotDelayMuteBeyondCap() {
        // Glass.aiff reports a 1.65s duration but is mostly inaudible decay
        // tail; the mute must not wait for the whole file.
        XCTAssertEqual(SystemAudioManager.muteDelay(afterChimeOf: 1.65), SystemAudioManager.maxChimeMuteDelay)
        XCTAssertLessThanOrEqual(SystemAudioManager.maxChimeMuteDelay, 0.5)
    }

    func testNegativeDurationClampsToZero() {
        XCTAssertEqual(SystemAudioManager.muteDelay(afterChimeOf: -1), 0)
    }
}
