import Foundation

/// An amplitude gate, not a speech classifier. Favor quieter dictation without
/// diluting speech bursts with pauses.
struct RecordingActivity {
    // Require 100 ms at or above -50 dBFS across the recording.
    // Counting active time preserves speech bursts without letting a single
    // loud mic click count as speech. A whole-recording average cannot do both.
    private static let minimumRMS: Float = pow(10, -50 / 20.0)
    private static let minimumActiveDuration: Double = 0.1
    private var activeDuration: Double = 0

    var isSilent: Bool { activeDuration < Self.minimumActiveDuration }

    /// Count successfully recorded frames above the noise gate, regardless of
    /// pauses elsewhere in the capture or the microphone's sample rate.
    mutating func observe(rms: Float, frameCount: Int, sampleRate: Double) {
        guard rms.isFinite, rms >= Self.minimumRMS,
              frameCount > 0, sampleRate.isFinite, sampleRate > 0 else { return }
        activeDuration += Double(frameCount) / sampleRate
    }
}
