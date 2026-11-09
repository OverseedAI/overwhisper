import XCTest
@testable import Overwhisper

final class RecordingActivityTests: XCTestCase {
    private func rms(_ db: Float) -> Float { pow(10, db / 20) }

    func testReportedRecordingsWithSpeechPeaksReachTranscription() {
        // Match the reported mean/peak levels with speech bursts and pauses.
        // Both averages fall below the old -38 dBFS whole-recording cutoff.
        for (peakDB, activeBuffers, totalBuffers): (Float, Int, Int) in [
            (-28.1, 35, 370), (-27.6, 22, 255)
        ] {
            var activity = RecordingActivity()
            var energy: Float = 0
            for index in 0..<totalBuffers {
                let amplitude: Float = index < activeBuffers ? rms(peakDB) : 0
                energy += amplitude * amplitude
                activity.observe(rms: amplitude, frameCount: 320, sampleRate: 16_000)
            }
            XCTAssertLessThan(10 * log10(energy / Float(totalBuffers)), -38)
            XCTAssertFalse(activity.isSilent, "Speech peaks must survive a low overall average")
        }
    }

    func testSustainedMicNoiseStillCannotReachTranscription() {
        for db: Float in [-50, -45, -40] {
            var activity = RecordingActivity()
            activity.observe(rms: rms(db), frameCount: 160_000, sampleRate: 16_000)
            XCTAssertTrue(activity.isSilent, "Preserve the original protection against mic noise")
        }
    }

    func testPausesDoNotDiluteShortUtterance() {
        var activity = RecordingActivity()
        activity.observe(rms: 0, frameCount: 160_000, sampleRate: 16_000)
        activity.observe(rms: rms(-35), frameCount: 3_200, sampleRate: 16_000)
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
                activity.observe(rms: rms(-35), frameCount: Int(rate / 100), sampleRate: rate)
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
