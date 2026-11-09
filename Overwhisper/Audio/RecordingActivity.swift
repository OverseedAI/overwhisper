import Foundation

/// An amplitude gate, not a speech classifier. Preserve the original noise floor
/// protection without diluting speech bursts with pauses.
struct RecordingActivity {
    // Require 100 ms above the original -38 dBFS floor across the recording.
    // Counting active time preserves speech bursts without letting a single
    // loud mic click count as speech. A whole-recording average cannot do both.
    // Keep the original noise rejection: a sustained -45 dBFS mic noise floor
    // must not trigger Whisper's hallucinations on non-speech input.
    private static let minimumRMS: Float = pow(10, -38 / 20.0)
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
