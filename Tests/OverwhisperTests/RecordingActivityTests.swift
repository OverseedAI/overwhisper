import XCTest
@testable import Overwhisper

final class RecordingActivityTests: XCTestCase {
    private func rms(_ db: Float) -> Float { pow(10, db / 20) }

    func testReportedQuietRecordingsReachTranscription() {
        for db: Float in [-38.3, -38.1, -48] {
            var activity = RecordingActivity()
            for _ in 0..<250 {
                activity.observe(rms: rms(db), frameCount: 320, sampleRate: 16_000)
            }
            XCTAssertFalse(activity.isSilent, "Quiet audio at \(db) dBFS must reach the engine")
        }
    }

    func testPausesDoNotDiluteShortUtterance() {
        var activity = RecordingActivity()
        activity.observe(rms: 0, frameCount: 160_000, sampleRate: 16_000)
        activity.observe(rms: rms(-45), frameCount: 3_200, sampleRate: 16_000)
        activity.observe(rms: 0, frameCount: 160_000, sampleRate: 16_000)
        XCTAssertFalse(activity.isSilent)
    }

    func testSilenceAndVeryLowNoiseAreSkipped() {
        for amplitude: Float in [0, rms(-65), rms(-55)] {
            var activity = RecordingActivity()
            activity.observe(rms: amplitude, frameCount: 160_000, sampleRate: 16_000)
            XCTAssertTrue(activity.isSilent)
        }
    }

    func testSingleLoudClickDoesNotCountAsSustainedAudio() {
        var activity = RecordingActivity()
        activity.observe(rms: 0, frameCount: 16_000, sampleRate: 16_000)
        activity.observe(rms: rms(-10), frameCount: 320, sampleRate: 16_000)
        activity.observe(rms: 0, frameCount: 16_000, sampleRate: 16_000)
        XCTAssertTrue(activity.isSilent)
    }

    func testActiveDurationDoesNotDependOnSampleRateOrBufferSize() {
        for rate: Double in [16_000, 44_100, 48_000] {
            var activity = RecordingActivity()
            for _ in 0..<20 {
                activity.observe(rms: rms(-40), frameCount: Int(rate / 100), sampleRate: rate)
            }
            XCTAssertFalse(activity.isSilent)
        }
    }

    func testNewRecordingResetsActivity() {
        var activity = RecordingActivity()
        activity.observe(rms: rms(-35), frameCount: 16_000, sampleRate: 16_000)
        activity = RecordingActivity()
        XCTAssertTrue(activity.isSilent)
    }
}
