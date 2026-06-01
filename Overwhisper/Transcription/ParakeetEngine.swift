import FluidAudio
import Foundation

actor ParakeetEngine: TranscriptionEngine {
    private var asrManager: AsrManager?
    private let appState: AppState
    private var isInitialized = false
    private var isInitializing = false
    private var currentModelType: ParakeetModelType?

    init(appState: AppState) {
        self.appState = appState
    }

    func initialize() async throws {
        guard !isInitializing else {
            AppLogger.transcription.debug("Parakeet initialization already in progress, skipping")
            return
        }
        isInitializing = true
        defer { isInitializing = false }

        let modelType = await appState.parakeetModel
        let modelChanged = currentModelType != modelType

        if isInitialized && !modelChanged {
            return
        }

        asrManager = nil
        isInitialized = false
        currentModelType = modelType

        let modelVersion: AsrModelVersion = modelType == .v2English ? .v2 : .v3
        AppLogger.transcription.info("Initializing Parakeet with model: \(modelType.rawValue)")

        await MainActor.run {
            appState.isDownloadingModel = true
            appState.currentlyDownloadingModel = modelType.rawValue
        }

        do {
            let models = try await AsrModels.downloadAndLoad(version: modelVersion)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            asrManager = manager
            isInitialized = true

            await MainActor.run {
                appState.isDownloadingModel = false
                appState.currentlyDownloadingModel = nil
                appState.parakeetDownloadedModels.insert(modelType.rawValue)
            }

            AppLogger.transcription.info("Parakeet initialized successfully")
        } catch {
            isInitialized = false
            asrManager = nil

            await MainActor.run {
                appState.isDownloadingModel = false
                appState.currentlyDownloadingModel = nil
                appState.lastError = "Failed to initialize Parakeet: \(error.localizedDescription)"
            }

            AppLogger.transcription.error("Failed to initialize Parakeet: \(error.localizedDescription)")
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

extension ParakeetEngine {
    /// Downloads model weights without changing the user's active engine/model selection.
    /// Reports progress and errors via AppState.
    @MainActor
    static func download(modelType: ParakeetModelType, appState: AppState) async {
        let version: AsrModelVersion = modelType == .v2English ? .v2 : .v3

        appState.isDownloadingModel = true
        appState.currentlyDownloadingModel = modelType.rawValue
        defer {
            appState.isDownloadingModel = false
            appState.currentlyDownloadingModel = nil
        }

        do {
            _ = try await AsrModels.download(version: version)
            appState.parakeetDownloadedModels.insert(modelType.rawValue)
            AppLogger.transcription.info("Downloaded Parakeet model: \(modelType.rawValue)")
        } catch {
            appState.lastError = "Failed to download \(modelType.displayName): \(error.localizedDescription)"
            AppLogger.transcription.error("Failed to download Parakeet model \(modelType.rawValue): \(error.localizedDescription)")
        }
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
