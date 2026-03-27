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

    private static let maxRetries = 3
    private static let retryDelaySeconds: UInt64 = 5

    func initialize() async {
        // Prevent concurrent initialization - check and set atomically before any await
        guard !isInitializing else {
            AppLogger.transcription.debug("WhisperKit initialization already in progress, skipping")
            return
        }
        isInitializing = true

        defer { isInitializing = false }

        let modelName = await appState.whisperModel.rawValue

        // Skip if already initialized with the same model
        if isInitialized && currentModel == modelName {
            return
        }

        AppLogger.transcription.info("Initializing WhisperKit with model: \(modelName)")

        // Check if model is already downloaded locally to avoid network dependency
        let cachedModelFolder = await modelManager.findModelFolder(for: modelName)
        let modelAlreadyDownloaded = cachedModelFolder != nil

        if let folder = cachedModelFolder {
            AppLogger.transcription.info("Using cached model at: \(folder)")
        }

        for attempt in 1...Self.maxRetries {
            do {
                await MainActor.run {
                    appState.isDownloadingModel = true
                }

                whisperKit = try await WhisperKit(
                    model: modelName,
                    modelFolder: cachedModelFolder,
                    computeOptions: ModelComputeOptions(
                        audioEncoderCompute: .cpuAndNeuralEngine,
                        textDecoderCompute: .cpuAndNeuralEngine
                    ),
                    verbose: true,
                    logLevel: .debug,
                    prewarm: true,
                    load: true,
                    download: !modelAlreadyDownloaded
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

                AppLogger.transcription.info("WhisperKit initialized successfully")
                return

            } catch {
                AppLogger.transcription.error("Failed to initialize WhisperKit (attempt \(attempt)/\(Self.maxRetries)): \(error.localizedDescription)")

                if attempt < Self.maxRetries {
                    AppLogger.transcription.info("Retrying in \(Self.retryDelaySeconds) seconds...")
                    try? await Task.sleep(nanoseconds: Self.retryDelaySeconds * 1_000_000_000)
                } else {
                    await MainActor.run {
                        appState.isDownloadingModel = false
                        appState.lastError = "Failed to initialize WhisperKit: \(error.localizedDescription)"
                    }
                }
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

        AppLogger.transcription.debug("Transcribing audio from: \(audioURL.path)")

        // Get language and task settings
        let language = await appState.language
        let shouldTranslate = await appState.translateToEnglish

        // When auto-detect is selected, detect language first to avoid English bias
        let resolvedLanguage: String?
        if language == "auto" {
            let detected = try? await whisperKit.detectLanguage(audioPath: audioURL.path)
            resolvedLanguage = detected?.language
            if let lang = resolvedLanguage {
                AppLogger.transcription.debug("Auto-detected language: \(lang)")
            }
        } else {
            resolvedLanguage = language
        }

        let decodingOptions = DecodingOptions(
            verbose: true,
            task: shouldTranslate ? .translate : .transcribe,
            language: resolvedLanguage,
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

        AppLogger.transcription.debug("Transcription result: \(text)")

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
