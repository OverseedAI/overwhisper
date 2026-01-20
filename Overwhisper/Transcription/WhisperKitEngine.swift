import Foundation
import WhisperKit

actor WhisperKitEngine: TranscriptionEngine {
    private var whisperKit: WhisperKit?
    private let appState: AppState
    private let modelManager: ModelManager
    private var isInitialized = false
    private var currentModel: String?

    init(appState: AppState, modelManager: ModelManager) {
        self.appState = appState
        self.modelManager = modelManager
    }

    func initialize() async {
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

        let results = try await whisperKit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: decodingOptions
        )

        // Combine all segments into final text
        let text = results.compactMap { $0.text }.joined(separator: " ")

        print("Transcription result: \(text)")

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum WhisperKitError: LocalizedError {
    case notInitialized
    case modelNotFound
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "WhisperKit is not initialized"
        case .modelNotFound:
            return "Whisper model not found"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        }
    }
}
