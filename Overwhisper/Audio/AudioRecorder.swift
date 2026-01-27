import AVFoundation
import Foundation
import Combine
import CoreAudio
import AudioToolbox

struct AudioInputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let uid: String
}

@MainActor
class AudioDeviceManager: ObservableObject {
    @Published private(set) var inputDevices: [AudioInputDevice] = []
    @Published private(set) var defaultInputDeviceID: AudioDeviceID?

    private var devicesListener: AudioObjectPropertyListenerBlock?
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?

    init() {
        refreshDevices()
        startMonitoring()
    }

    func device(forUID uid: String) -> AudioInputDevice? {
        inputDevices.first { $0.uid == uid }
    }

    var defaultInputDeviceName: String? {
        guard let defaultID = defaultInputDeviceID else { return nil }
        return inputDevices.first { $0.id == defaultID }?.name
    }

    func refreshDevices() {
        let devices = AudioDeviceManager.fetchInputDevices()
        let defaultID = AudioDeviceManager.defaultInputDeviceID()

        inputDevices = devices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        defaultInputDeviceID = defaultID
    }

    private func startMonitoring() {
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let devicesListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshDevices()
            }
        }

        let defaultDeviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshDevices()
            }
        }

        self.devicesListener = devicesListener
        self.defaultDeviceListener = defaultDeviceListener

        AudioObjectAddPropertyListenerBlock(systemObjectID, &devicesAddress, DispatchQueue.main, devicesListener)
        AudioObjectAddPropertyListenerBlock(systemObjectID, &defaultDeviceAddress, DispatchQueue.main, defaultDeviceListener)
    }

    private func stopMonitoring() {
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        if let devicesListener {
            AudioObjectRemovePropertyListenerBlock(systemObjectID, &devicesAddress, DispatchQueue.main, devicesListener)
        }

        if let defaultDeviceListener {
            AudioObjectRemovePropertyListenerBlock(systemObjectID, &defaultDeviceAddress, DispatchQueue.main, defaultDeviceListener)
        }
    }

    private static func fetchInputDevices() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(systemObjectID, &address, 0, nil, &dataSize) == noErr else {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return []
        }

        return deviceIDs.compactMap { deviceID in
            guard deviceHasInput(deviceID) else { return nil }
            guard let name = deviceName(deviceID),
                  let uid = deviceUID(deviceID) else {
                return nil
            }
            return AudioInputDevice(id: deviceID, name: name, uid: uid)
        }
    }

    nonisolated static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        let status = AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &dataSize, &deviceID)
        guard status == noErr else { return nil }
        return deviceID
    }

    private static func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &name)
        guard status == noErr else { return nil }
        return name as String
    }

    private static func deviceUID(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &uid)
        guard status == noErr else { return nil }
        return uid as String
    }

    private static func deviceHasInput(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else {
            return false
        }
        guard dataSize >= UInt32(MemoryLayout<AudioBufferList>.size) else {
            return false
        }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        bufferListPointer.initializeMemory(as: UInt8.self, repeating: 0, count: Int(dataSize))
        defer { bufferListPointer.deallocate() }

        var dataSizeCopy = dataSize
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSizeCopy,
            bufferListPointer
        )
        guard status == noErr else { return false }

        let bufferList = bufferListPointer.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }
}

class AudioRecorder: ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var selectedInputDeviceID: AudioDeviceID?
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?

    @Published var currentLevel: Float = 0.0
    @Published var isRecording: Bool = false

    private let sampleRate: Double = 16000  // Whisper optimal
    private let channels: AVAudioChannelCount = 1  // Mono

    private var levelUpdateTimer: Timer?

    init() {}

    func setInputDevice(_ device: AudioInputDevice?) {
        selectedInputDeviceID = device?.id

        if !audioEngine.isRunning {
            try? applyInputDevice()
        }
    }

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

        do {
            try applyInputDevice()
        } catch {
            selectedInputDeviceID = nil
            try applyInputDevice()
        }
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioRecorderError.invalidFormat
        }

        // Create the recording format (16kHz, mono, 16-bit PCM)
        guard let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ) else {
            throw AudioRecorderError.invalidFormat
        }

        converter = nil
        converterInputFormat = nil

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
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer, recordingFormat: recordingFormat)
        }

        try audioEngine.start()
        isRecording = true

        // Start level monitoring
        startLevelMonitoring()
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, recordingFormat: AVAudioFormat) {
        // Calculate audio level for visualization
        updateAudioLevel(buffer: buffer)

        guard let converter = ensureConverter(for: buffer.format, recordingFormat: recordingFormat) else {
            return
        }

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
                AppLogger.audio.error("Error writing audio buffer: \(error.localizedDescription)")
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

        // Normalize to 0-1 range (using -40dB to 0dB range for less sensitivity)
        let normalizedLevel = max(0, min(1, (level + 40) / 40))

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
        converter = nil
        converterInputFormat = nil

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
        converter = nil
        converterInputFormat = nil

        // Delete the temporary file
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }

        isRecording = false
        currentLevel = 0
        recordingURL = nil
    }

    /// Resets the audio engine after system wake or audio route changes.
    /// This ensures the engine is ready for the next recording session.
    func resetAudioEngine() {
        // Stop engine if running (shouldn't be after wake, but be safe)
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }

        // Reset the audio engine to clear any stale state
        audioEngine.reset()
        audioEngine = AVAudioEngine()

        isRecording = false
        currentLevel = 0
        audioFile = nil
        recordingURL = nil
        converter = nil
        converterInputFormat = nil

        if let selectedInputDeviceID {
            try? applyInputDevice()
        }
    }

    private func ensureConverter(for inputFormat: AVAudioFormat, recordingFormat: AVAudioFormat) -> AVAudioConverter? {
        if let converter = converter, let cachedFormat = converterInputFormat, formatsMatch(cachedFormat, inputFormat) {
            return converter
        }

        guard let newConverter = AVAudioConverter(from: inputFormat, to: recordingFormat) else {
            return nil
        }

        converter = newConverter
        converterInputFormat = inputFormat
        return newConverter
    }

    private func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.commonFormat == rhs.commonFormat
            && lhs.isInterleaved == rhs.isInterleaved
    }

    func applyInputDevice() throws {
        guard let audioUnit = audioEngine.inputNode.audioUnit else {
            throw AudioRecorderError.deviceConfigurationFailed
        }

        let deviceID = selectedInputDeviceID ?? AudioDeviceManager.defaultInputDeviceID()
        guard var targetDeviceID = deviceID else { return }

        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &targetDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard status == noErr else {
            throw AudioRecorderError.deviceConfigurationFailed
        }
    }
}

enum AudioRecorderError: LocalizedError {
    case failedToCreateFile
    case invalidFormat
    case converterCreationFailed
    case notRecording
    case noPermission
    case deviceConfigurationFailed

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
        case .deviceConfigurationFailed:
            return "Failed to configure input device"
        }
    }
}
