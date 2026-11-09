import Foundation

/// A conservative amplitude gate, not a speech classifier. Let the transcription
/// engine handle quiet speech; only skip recordings without sustained audio.
struct RecordingActivity {
    // Require 100 ms above -50 dBFS across the recording. Counting active time
    // preserves quiet utterances surrounded by pauses without letting a single
    // loud mic click count as speech. A whole-recording average cannot do both.
    private static let minimumRMS: Float = pow(10, -50 / 20.0)
    private static let minimumActiveDuration: Double = 0.1
    private var activeDuration: Double = 0

    var isSilent: Bool { activeDuration < Self.minimumActiveDuration }

    mutating func observe(rms: Float, frameCount: Int, sampleRate: Double) {
        guard rms.isFinite, rms >= Self.minimumRMS,
              frameCount > 0, sampleRate.isFinite, sampleRate > 0 else { return }
        activeDuration += Double(frameCount) / sampleRate
    }
}
