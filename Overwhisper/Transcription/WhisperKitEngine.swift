import Foundation
import WhisperKit

actor WhisperKitEngine: TranscriptionEngine {
    private var whisperKit: WhisperKit?
    private let appState: AppState
    private let modelManager: ModelManager
    private var isInitialized = false

    init(appState: AppState, modelManager: ModelManager) {
        self.appState = appState
        self.modelManager = modelManager
    }

    func initialize() async {
        guard !isInitialized else { return }

        do {
            // Get the model path
            let modelName = await appState.whisperModel.rawValue

            // Check if model is downloaded
            let modelPath = try await modelManager.getModelPath(for: modelName)

            if let path = modelPath {
                // Initialize WhisperKit with the local model
                whisperKit = try await WhisperKit(
                    modelFolder: path,
                    computeOptions: getComputeOptions(),
                    verbose: false,
                    logLevel: .none
                )
            } else {
                // Download the model first
                await MainActor.run {
                    appState.isDownloadingModel = true
                }

                whisperKit = try await WhisperKit(
                    model: modelName,
                    computeOptions: getComputeOptions(),
                    verbose: false,
                    logLevel: .none,
                    prewarm: true,
                    load: true,
                    download: true
                )

                await MainActor.run {
                    appState.isDownloadingModel = false
                    appState.isModelDownloaded = true
                }
            }

            isInitialized = true

            await MainActor.run {
                appState.isModelDownloaded = true
            }

        } catch {
            print("Failed to initialize WhisperKit: \(error)")
            await MainActor.run {
                appState.isDownloadingModel = false
                appState.lastError = "Failed to initialize WhisperKit: \(error.localizedDescription)"
            }
        }
    }

    private func getComputeOptions() -> ModelComputeOptions {
        return ModelComputeOptions(
            audioEncoderCompute: .cpuAndNeuralEngine,
            textDecoderCompute: .cpuAndNeuralEngine
        )
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let whisperKit = whisperKit else {
            throw WhisperKitError.notInitialized
        }

        // Get language setting
        let language = await appState.language
        let decodingOptions = DecodingOptions(
            verbose: false,
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
