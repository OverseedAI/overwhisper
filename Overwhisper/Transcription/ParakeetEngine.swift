import FluidAudio
import Foundation

actor ParakeetEngine: TranscriptionEngine {
    private var asrManager: AsrManager?
    private let appState: AppState
    private var isInitialized = false
    private var currentModelType: ParakeetModelType?

    init(appState: AppState) {
        self.appState = appState
    }

    func initialize() async throws {
        let modelType = await appState.parakeetModel
        let modelChanged = currentModelType != modelType

        if isInitialized && !modelChanged {
            AppLogger.transcription.debug("Parakeet already initialized with same model")
            return
        }

        asrManager = nil
        isInitialized = false
        currentModelType = modelType

        let modelVersion: AsrModelVersion = modelType == .v2English ? .v2 : .v3
        let versionString = modelVersion == .v2 ? "v2" : "v3"
        AppLogger.transcription.info("Initializing Parakeet engine with model: \(modelType.displayName) (version: \(versionString))")

        await MainActor.run {
            appState.isDownloadingModel = true
            appState.isModelDownloaded = false
        }

        do {
            AppLogger.transcription.debug("Downloading/loading Parakeet models...")
            let models = try await AsrModels.downloadAndLoad(version: modelVersion)
            AppLogger.transcription.debug("Loading ASR manager...")
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            asrManager = manager
            isInitialized = true

            await MainActor.run {
                appState.isDownloadingModel = false
                appState.isModelDownloaded = true
                appState.downloadedModels.insert(modelType.rawValue)
            }

            AppLogger.transcription.info("Parakeet engine initialized successfully")
        } catch {
            isInitialized = false
            asrManager = nil

            await MainActor.run {
                appState.isDownloadingModel = false
                appState.isModelDownloaded = false
                appState.lastError = "Failed to initialize Parakeet: \(error.localizedDescription)"
            }

            AppLogger.transcription.error("Failed to initialize Parakeet engine: \(error.localizedDescription)")
            throw ParakeetError.initializationFailed(error.localizedDescription)
        }
    }

    func transcribe(audioURL: URL) async throws -> String {
        do {
            try await initialize()
        } catch {
            AppLogger.transcription.error("Failed to initialize Parakeet before transcription: \(error.localizedDescription)")
            throw error
        }

        guard let asrManager else {
            throw ParakeetError.notInitialized
        }

        AppLogger.transcription.debug("Transcribing audio from: \(audioURL.path)")
        var decoderState = TdtDecoderState.make(decoderLayers: await asrManager.decoderLayerCount)
        let result = try await asrManager.transcribe(
            audioURL,
            decoderState: &decoderState,
            language: await languageHint()
        )
        AppLogger.transcription.debug("Transcription result: \(result.text)")

        return result.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    private func languageHint() async -> Language? {
        let code = await appState.language
        guard code != "auto" else { return nil }
        return Language(rawValue: code)
    }
}

enum ParakeetError: LocalizedError {
    case notInitialized
    case initializationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Parakeet engine is not initialized"
        case .initializationFailed(let message):
            return "Parakeet initialization failed: \(message)"
        }
    }
}
