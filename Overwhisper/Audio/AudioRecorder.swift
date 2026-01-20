import AVFoundation
import Foundation
import Combine

class AudioRecorder: ObservableObject {
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?

    @Published var currentLevel: Float = 0.0
    @Published var isRecording: Bool = false

    private let sampleRate: Double = 16000  // Whisper optimal
    private let channels: AVAudioChannelCount = 1  // Mono

    private var levelUpdateTimer: Timer?

    init() {}

    func startRecording() throws {
        guard !isRecording else { return }

        // Create temporary file for recording
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "overwhisper_recording_\(UUID().uuidString).wav"
        recordingURL = tempDir.appendingPathComponent(fileName)

        guard let url = recordingURL else {
            throw AudioRecorderError.failedToCreateFile
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create the recording format (16kHz, mono, 16-bit PCM)
        guard let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ) else {
            throw AudioRecorderError.invalidFormat
        }

        // Create converter from input format to recording format
        guard let converter = AVAudioConverter(from: inputFormat, to: recordingFormat) else {
            throw AudioRecorderError.converterCreationFailed
        }

        // Create the audio file
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: true
        )!

        audioFile = try AVAudioFile(
            forWriting: url,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer, converter: converter, recordingFormat: recordingFormat)
        }

        try audioEngine.start()
        isRecording = true

        // Start level monitoring
        startLevelMonitoring()
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, recordingFormat: AVAudioFormat) {
        // Calculate audio level for visualization
        updateAudioLevel(buffer: buffer)

        // Convert and write to file
        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * sampleRate / buffer.format.sampleRate)

        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: recordingFormat, frameCapacity: frameCount) else {
            return
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

        if error == nil {
            do {
                try audioFile?.write(from: convertedBuffer)
            } catch {
                print("Error writing audio buffer: \(error)")
            }
        }
    }

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)

        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameLength))
        let level = 20 * log10(max(rms, 0.000001))

        // Normalize to 0-1 range (assuming -60dB to 0dB range)
        let normalizedLevel = max(0, min(1, (level + 60) / 60))

        DispatchQueue.main.async { [weak self] in
            self?.currentLevel = normalizedLevel
        }
    }

    private func startLevelMonitoring() {
        // Level updates happen in the audio tap callback
        // Timer kept for potential future use (e.g., decay animation)
        levelUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            // Reserved for level decay animation if needed
        }
    }

    func stopRecording() throws -> URL {
        guard isRecording, let url = recordingURL else {
            throw AudioRecorderError.notRecording
        }

        // Stop level monitoring
        levelUpdateTimer?.invalidate()
        levelUpdateTimer = nil

        // Stop engine and remove tap
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        // Close the audio file
        audioFile = nil

        isRecording = false
        currentLevel = 0

        // Verify the file was created
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioRecorderError.failedToCreateFile
        }

        return url
    }

    func cancelRecording() {
        guard isRecording else { return }

        levelUpdateTimer?.invalidate()
        levelUpdateTimer = nil

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioFile = nil

        // Delete the temporary file
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }

        isRecording = false
        currentLevel = 0
        recordingURL = nil
    }
}

enum AudioRecorderError: LocalizedError {
    case failedToCreateFile
    case invalidFormat
    case converterCreationFailed
    case notRecording
    case noPermission

    var errorDescription: String? {
        switch self {
        case .failedToCreateFile:
            return "Failed to create audio file"
        case .invalidFormat:
            return "Invalid audio format"
        case .converterCreationFailed:
            return "Failed to create audio converter"
        case .notRecording:
            return "Not currently recording"
        case .noPermission:
            return "Microphone permission not granted"
        }
    }
}
