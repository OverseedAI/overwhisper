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
    // Input-only HAL audio unit. We deliberately avoid AVAudioEngine here: its
    // render loop is clocked by the system default *output* device, so a flaky
    // output (e.g. Bluetooth headphones) can break input capture even when the
    // mic itself is fine. A HAL output unit in input-only mode binds to exactly
    // one input device and never opens an output/speaker device.
    private var inputUnit: AudioUnit?
    private var clientFormat: AVAudioFormat?
    private var recordingFormat: AVAudioFormat?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var selectedInputDeviceID: AudioDeviceID?
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?

    @Published var currentLevel: Float = 0.0
    @Published var isRecording: Bool = false

    /// Highest per-buffer RMS amplitude (linear, 0..1) observed during the most
    /// recent recording. Reset on each `startRecording()` call.
    private(set) var peakRMS: Float = 0

    /// Mean RMS amplitude (linear, 0..1) across the entire most recent recording,
    /// computed as `sqrt(sumOfSquares / totalFrames)` over the raw mic channel.
    /// Reset on each `startRecording()` call. Use this — not `peakRMS` — to gate
    /// silent recordings, because a single mic transient can push peak above any
    /// threshold even when the bulk of the recording is silence.
    private(set) var meanRMS: Float = 0

    private var sumOfSquares: Double = 0
    private var totalSamples: Int = 0

    private let sampleRate: Double = 16000  // Whisper optimal
    private let channels: AVAudioChannelCount = 1  // Mono

    private var levelUpdateTimer: Timer?

    init() {}

    func setInputDevice(_ device: AudioInputDevice?) {
        // The device is bound when recording actually starts (makeInputUnit),
        // so here we only remember the selection.
        selectedInputDeviceID = device?.id
    }

    func startRecording() throws {
        guard !isRecording else { return }
        loggedOnce.removeAll()
        peakRMS = 0
        meanRMS = 0
        sumOfSquares = 0
        totalSamples = 0

        // Check microphone permission before opening the device
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined, .denied, .restricted:
            throw AudioRecorderError.noPermission
        @unknown default:
            throw AudioRecorderError.noPermission
        }

        // Create temporary file for recording
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "overwhisper_recording_\(UUID().uuidString).wav"
        let url = tempDir.appendingPathComponent(fileName)
        recordingURL = url

        // Resolve the input device: explicit selection, else the system default
        // input. A HAL unit defaults to the default *output* device, so the input
        // device must always be bound explicitly.
        guard let deviceID = selectedInputDeviceID ?? AudioDeviceManager.defaultInputDeviceID() else {
            throw AudioRecorderError.deviceConfigurationFailed
        }

        // Build the input unit, falling back to the default input device if the
        // explicitly-selected one can't be opened.
        let unit: AudioUnit
        let client: AVAudioFormat
        do {
            (unit, client) = try makeInputUnit(deviceID: deviceID)
        } catch {
            guard let fallback = AudioDeviceManager.defaultInputDeviceID(), fallback != deviceID else {
                throw error
            }
            AppLogger.audio.error("Input device \(deviceID) failed to open — falling back to system default")
            selectedInputDeviceID = nil
            (unit, client) = try makeInputUnit(deviceID: fallback)
        }
        inputUnit = unit
        clientFormat = client

        AppLogger.audio.info(
            "Recording start — device id \(deviceID) (\(self.selectedInputDeviceID == nil ? "system default" : "selected")), input format: \(client.sampleRate) Hz, \(client.channelCount) ch"
        )

        // Target format for transcription: 16kHz mono float32
        guard let recording = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ) else {
            cleanupAfterFailure()
            throw AudioRecorderError.invalidFormat
        }
        recordingFormat = recording

        converter = nil
        converterInputFormat = nil

        // On-disk format: 16kHz mono 16-bit PCM WAV
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: true
        )!

        do {
            audioFile = try AVAudioFile(
                forWriting: url,
                settings: outputFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            cleanupAfterFailure()
            throw error
        }

        // Wire the input render callback (passing self via the opaque refcon)
        var callbackStruct = AURenderCallbackStruct(
            inputProc: { inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, _ in
                let recorder = Unmanaged<AudioRecorder>.fromOpaque(inRefCon).takeUnretainedValue()
                return recorder.renderInput(
                    flags: ioActionFlags,
                    timeStamp: inTimeStamp,
                    busNumber: inBusNumber,
                    frameCount: inNumberFrames
                )
            },
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        var status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            0,
            &callbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        guard status == noErr else {
            AppLogger.audio.error("SetInputCallback failed: \(status)")
            cleanupAfterFailure()
            throw AudioRecorderError.deviceConfigurationFailed
        }

        status = AudioUnitInitialize(unit)
        guard status == noErr else {
            AppLogger.audio.error("AudioUnitInitialize failed: \(status)")
            cleanupAfterFailure()
            throw AudioRecorderError.deviceConfigurationFailed
        }

        status = AudioOutputUnitStart(unit)
        guard status == noErr else {
            AppLogger.audio.error("AudioOutputUnitStart failed: \(status)")
            cleanupAfterFailure()
            throw AudioRecorderError.deviceConfigurationFailed
        }

        isRecording = true

        // Start level monitoring
        startLevelMonitoring()
    }

    /// Pulls captured audio from the input unit and feeds it through the existing
    /// conversion/metering path. Runs on a realtime audio thread.
    private func renderInput(
        flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timeStamp: UnsafePointer<AudioTimeStamp>,
        busNumber: UInt32,
        frameCount: UInt32
    ) -> OSStatus {
        guard let unit = inputUnit, let clientFormat, let recordingFormat else {
            return noErr
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: clientFormat, frameCapacity: frameCount) else {
            logOnce("render-alloc") {
                AppLogger.audio.error("Failed to allocate render buffer (\(frameCount) frames)")
            }
            return noErr
        }
        buffer.frameLength = frameCount

        let status = AudioUnitRender(unit, flags, timeStamp, busNumber, frameCount, buffer.mutableAudioBufferList)
        guard status == noErr else {
            logOnce("render-error") {
                AppLogger.audio.error("AudioUnitRender failed: \(status)")
            }
            return status
        }

        processAudioBuffer(buffer, recordingFormat: recordingFormat)
        return noErr
    }

    /// Creates an input-only HAL audio unit bound to `deviceID`, configured to
    /// deliver float32 non-interleaved audio at the device's native rate/channels.
    private func makeInputUnit(deviceID: AudioDeviceID) throws -> (AudioUnit, AVAudioFormat) {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &desc) else {
            throw AudioRecorderError.deviceConfigurationFailed
        }

        var unitOptional: AudioUnit?
        var status = AudioComponentInstanceNew(component, &unitOptional)
        guard status == noErr, let unit = unitOptional else {
            throw AudioRecorderError.deviceConfigurationFailed
        }

        func fail(_ message: String) -> AudioRecorderError {
            AppLogger.audio.error("\(message)")
            AudioComponentInstanceDispose(unit)
            return AudioRecorderError.deviceConfigurationFailed
        }

        let flagSize = UInt32(MemoryLayout<UInt32>.size)

        // Enable input (bus 1), disable output (bus 0): input-only.
        var enableInput: UInt32 = 1
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enableInput, flagSize)
        guard status == noErr else { throw fail("EnableIO(input) failed: \(status)") }

        var disableOutput: UInt32 = 0
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disableOutput, flagSize)
        guard status == noErr else { throw fail("DisableIO(output) failed: \(status)") }

        // Bind to the chosen input device — never an output device.
        var device = deviceID
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw fail("Set CurrentDevice failed: \(status)") }

        // Read the device's native input format (input scope, bus 1).
        var hwFormat = AudioStreamBasicDescription()
        var fmtSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &hwFormat, &fmtSize)
        guard status == noErr, hwFormat.mSampleRate > 0, hwFormat.mChannelsPerFrame > 0 else {
            throw fail("Get hardware StreamFormat failed: \(status), rate=\(hwFormat.mSampleRate), ch=\(hwFormat.mChannelsPerFrame)")
        }

        // Ask the unit to hand us float32 non-interleaved at that rate/channels
        // (output scope, bus 1 — i.e. the format delivered to our callback).
        guard let client = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: hwFormat.mSampleRate,
            channels: hwFormat.mChannelsPerFrame,
            interleaved: false
        ) else {
            throw fail("Unsupported client format: \(hwFormat.mSampleRate) Hz, \(hwFormat.mChannelsPerFrame) ch")
        }
        var clientASBD = client.streamDescription.pointee
        status = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &clientASBD, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        guard status == noErr else { throw fail("Set client StreamFormat failed: \(status)") }

        return (unit, client)
    }

    /// Stops, uninitializes and disposes the input unit. Safe to call even if the
    /// unit was never started/initialized (those calls just no-op with an error).
    private func teardownInputUnit() {
        guard let unit = inputUnit else { return }
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        inputUnit = nil
    }

    /// Tears down a half-built recording session after a setup failure.
    private func cleanupAfterFailure() {
        teardownInputUnit()
        audioFile = nil
        converter = nil
        converterInputFormat = nil
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, recordingFormat: AVAudioFormat) {
        // Calculate audio level for visualization
        updateAudioLevel(buffer: buffer)

        guard let converter = ensureConverter(for: buffer.format, recordingFormat: recordingFormat) else {
            logOnce("converter-nil") {
                AppLogger.audio.error(
                    "Failed to obtain audio converter — buffer format: \(buffer.format), target: \(recordingFormat)"
                )
            }
            return
        }

        // Convert and write to file
        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * sampleRate / buffer.format.sampleRate)

        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: recordingFormat, frameCapacity: frameCount) else {
            logOnce("buffer-alloc-failed") {
                AppLogger.audio.error(
                    "Failed to allocate converted buffer (frameCount=\(frameCount), format=\(recordingFormat))"
                )
            }
            return
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        let status = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

        if let error {
            logOnce("convert-error") {
                AppLogger.audio.error(
                    "Audio convert error (status=\(status.rawValue)): \(error.localizedDescription)"
                )
            }
            return
        }

        if convertedBuffer.frameLength == 0 {
            logOnce("convert-empty") {
                AppLogger.audio.error(
                    "Converter produced 0 frames (status=\(status.rawValue), input frames=\(buffer.frameLength), input rms=\(self.bufferRMS(buffer)))"
                )
            }
            return
        }

        do {
            try audioFile?.write(from: convertedBuffer)
        } catch {
            AppLogger.audio.error("Error writing audio buffer: \(error.localizedDescription)")
        }
    }

    private var loggedOnce: Set<String> = []
    private func logOnce(_ key: String, _ action: () -> Void) {
        guard !loggedOnce.contains(key) else { return }
        loggedOnce.insert(key)
        action()
    }

    private func bufferRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return -1 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count {
            sum += channelData[i] * channelData[i]
        }
        return sqrt(sum / Float(count))
    }

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)

        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }

        sumOfSquares += Double(sum)
        totalSamples += frameLength

        let rms = sqrt(sum / Float(frameLength))
        if rms > peakRMS { peakRMS = rms }
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

        // Stop and dispose the input unit
        teardownInputUnit()

        // Close the audio file
        audioFile = nil
        converter = nil
        converterInputFormat = nil

        isRecording = false
        currentLevel = 0

        if totalSamples > 0 {
            meanRMS = Float(sqrt(sumOfSquares / Double(totalSamples)))
        } else {
            meanRMS = 0
        }

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

        teardownInputUnit()
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

    /// Tears down any active input unit after a system wake or audio route change
    /// so the next recording starts clean. Kept under the old name because callers
    /// (AppDelegate) invoke it on device changes and wake. The device is re-bound
    /// fresh on the next `startRecording()`, so nothing needs reapplying here.
    func resetAudioEngine() {
        levelUpdateTimer?.invalidate()
        levelUpdateTimer = nil

        teardownInputUnit()

        isRecording = false
        currentLevel = 0
        audioFile = nil
        recordingURL = nil
        converter = nil
        converterInputFormat = nil
    }

    private func ensureConverter(for inputFormat: AVAudioFormat, recordingFormat: AVAudioFormat) -> AVAudioConverter? {
        if let converter = converter, let cachedFormat = converterInputFormat, formatsMatch(cachedFormat, inputFormat) {
            return converter
        }

        guard let newConverter = AVAudioConverter(from: inputFormat, to: recordingFormat) else {
            return nil
        }

        // For multi-channel input devices (e.g., Scarlett Solo Gen 4 reports as 4 channels:
        // mic, instrument, loopback L, loopback R), AVAudioConverter's default downmix matrix
        // can produce silence when downmixing more than 2 channels to mono. Pin the converter
        // to take only channel 0 (the primary mic input) and drop the rest.
        if inputFormat.channelCount > 1 && recordingFormat.channelCount == 1 {
            newConverter.channelMap = [0]
            AppLogger.audio.info(
                "Configured converter channel map to [0] for \(inputFormat.channelCount)-ch input"
            )
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
