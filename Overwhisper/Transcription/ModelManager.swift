import Foundation
import WhisperKit

@MainActor
class ModelManager: ObservableObject {
    private let appState: AppState
    private let modelsDirectory: URL

    @Published var downloadedModels: Set<String> = []
    @Published var downloadProgress: [String: Double] = [:]

    init(appState: AppState) {
        self.appState = appState

        // Set up models directory in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.modelsDirectory = appSupport.appendingPathComponent("Overwhisper/Models", isDirectory: true)

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        // Scan for existing models
        scanForModels()
    }

    private func scanForModels() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        downloadedModels = Set(contents.compactMap { url -> String? in
            guard url.hasDirectoryPath else { return nil }
            return url.lastPathComponent
        })

        appState.isModelDownloaded = downloadedModels.contains(appState.whisperModel.rawValue)
    }

    func getModelPath(for modelName: String) async throws -> String? {
        let modelPath = modelsDirectory.appendingPathComponent(modelName)

        if FileManager.default.fileExists(atPath: modelPath.path) {
            return modelPath.path
        }

        return nil
    }

    func downloadModel(_ modelName: String) async throws {
        appState.isDownloadingModel = true
        appState.modelDownloadProgress = 0

        do {
            // Use WhisperKit's built-in download functionality
            _ = try await WhisperKit.download(
                variant: modelName,
                progressCallback: { progress in
                    Task { @MainActor in
                        self.appState.modelDownloadProgress = progress.fractionCompleted
                        self.downloadProgress[modelName] = progress.fractionCompleted
                    }
                }
            )

            // Model downloaded successfully
            downloadedModels.insert(modelName)
            appState.isModelDownloaded = true
            appState.isDownloadingModel = false
            appState.modelDownloadProgress = 1.0

        } catch {
            appState.isDownloadingModel = false
            appState.lastError = "Failed to download model: \(error.localizedDescription)"
            throw error
        }
    }

    func deleteModel(_ modelName: String) throws {
        let modelPath = modelsDirectory.appendingPathComponent(modelName)
        try FileManager.default.removeItem(at: modelPath)
        downloadedModels.remove(modelName)

        if modelName == appState.whisperModel.rawValue {
            appState.isModelDownloaded = false
        }
    }

    func isModelDownloaded(_ modelName: String) -> Bool {
        return downloadedModels.contains(modelName)
    }

    func availableModels() -> [WhisperModel] {
        return WhisperModel.allCases
    }

    func modelSize(_ model: WhisperModel) -> String {
        switch model {
        case .tiny, .tinyEn:
            return "~75 MB"
        case .base, .baseEn:
            return "~150 MB"
        case .small, .smallEn:
            return "~500 MB"
        case .medium, .mediumEn:
            return "~1.5 GB"
        case .large:
            return "~3 GB"
        case .largeTurbo:
            return "~1.6 GB"
        }
    }
}
