import Foundation
import WhisperKit

actor WhisperKitEngine: TranscriptionEngine {
    private var whisperKit: WhisperKit?
    private let appState: AppState
    private let modelManager: ModelManager
    private var isInitialized = false
    private var isInitializing = false
    private var currentModel: String?

    init(appState: AppState, modelManager: ModelManager) {
        self.appState = appState
        self.modelManager = modelManager
    }

    func initialize() async {
        // Prevent concurrent initialization - check and set atomically before any await
        guard !isInitializing else {
            print("WhisperKit initialization already in progress, skipping")
            return
        }
        isInitializing = true

        defer { isInitializing = false }

        let modelName = await appState.whisperModel.rawValue

        // Skip if already initialized with the same model
        if isInitialized && currentModel == modelName {
            return
        }

        print("Initializing WhisperKit with model: \(modelName)")

        do {
            await MainActor.run {
                appState.isDownloadingModel = true
            }

            // Let WhisperKit handle model downloading and loading
            whisperKit = try await WhisperKit(
                model: modelName,
                computeOptions: ModelComputeOptions(
                    audioEncoderCompute: .cpuAndNeuralEngine,
                    textDecoderCompute: .cpuAndNeuralEngine
                ),
                verbose: true,
                logLevel: .debug,
                prewarm: true,
                load: true,
                download: true
            )

            isInitialized = true
            currentModel = modelName

            await MainActor.run {
                appState.isDownloadingModel = false
                appState.isModelDownloaded = true
                appState.downloadedModels.insert(modelName)
            }

            // Refresh the model list
            await modelManager.scanForModels()

            print("WhisperKit initialized successfully")

        } catch {
            print("Failed to initialize WhisperKit: \(error)")
            await MainActor.run {
                appState.isDownloadingModel = false
                appState.lastError = "Failed to initialize WhisperKit: \(error.localizedDescription)"
            }
        }
    }

    private static let transcriptionTimeoutSeconds: UInt64 = 30

    func transcribe(audioURL: URL) async throws -> String {
        // Ensure initialized
        if !isInitialized {
            await initialize()
        }

        guard let whisperKit = whisperKit else {
            throw WhisperKitError.notInitialized
        }

        print("Transcribing audio from: \(audioURL.path)")

        // Get language setting
        let language = await appState.language
        let decodingOptions = DecodingOptions(
            verbose: true,
            task: .transcribe,
            language: language == "auto" ? nil : language,
            temperature: 0.0,
            temperatureFallbackCount: 5,
            sampleLength: 224,
            usePrefillPrompt: true,
            usePrefillCache: true,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            clipTimestamps: []
        )

        // Run transcription with timeout
        let text = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let results = try await whisperKit.transcribe(
                    audioPath: audioURL.path,
                    decodeOptions: decodingOptions
                )
                // Combine all segments into final text
                return results.compactMap { $0.text }.joined(separator: " ")
            }

            group.addTask {
                try await Task.sleep(nanoseconds: Self.transcriptionTimeoutSeconds * 1_000_000_000)
                throw WhisperKitError.timeout
            }

            // Return the first result (either transcription completes or timeout fires)
            guard let result = try await group.next() else {
                throw WhisperKitError.transcriptionFailed("No result")
            }

            // Cancel the other task
            group.cancelAll()

            return result
        }

        print("Transcription result: \(text)")

        return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}

enum WhisperKitError: LocalizedError {
    case notInitialized
    case modelNotFound
    case transcriptionFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "WhisperKit is not initialized"
        case .modelNotFound:
            return "Whisper model not found"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .timeout:
            return "Transcription timed out after 30 seconds"
        }
    }
}
