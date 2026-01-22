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

    func scanForModels() {
        var foundModels: Set<String> = []

        // Check multiple possible WhisperKit cache locations
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let homeDir = FileManager.default.homeDirectoryForCurrentUser

        let possiblePaths = [
            // MacWhisper's model directory
            appSupport.appendingPathComponent("MacWhisper/models/whisperkit/models/argmaxinc/whisperkit-coreml"),
            // SuperWhisper's model directory
            appSupport.appendingPathComponent("superwhisper/models/argmaxinc/whisperkit-coreml"),
            // Huggingface in Documents
            homeDir.appendingPathComponent("Documents/huggingface/models/argmaxinc/whisperkit-coreml"),
            // Standard huggingface cache in Application Support
            appSupport.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml"),
            // Huggingface cache in home directory
            homeDir.appendingPathComponent(".cache/huggingface/hub"),
            // Our custom directory
            modelsDirectory
        ]

        for basePath in possiblePaths {
            scanDirectory(basePath, foundModels: &foundModels)
        }

        print("Found models: \(foundModels)")

        downloadedModels = foundModels
        appState.downloadedModels = foundModels
        appState.isModelDownloaded = foundModels.contains(appState.whisperModel.rawValue)
    }

    private func scanDirectory(_ path: URL, foundModels: inout Set<String>) {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: nil) else {
            return
        }

        for url in contents where url.hasDirectoryPath {
            let name = url.lastPathComponent

            // Match patterns like "openai_whisper-small.en" or "openai_whisper-large-v3-v20240930"
            if name.starts(with: "openai_whisper-") {
                let rawName = String(name.dropFirst("openai_whisper-".count))
                // Extract base model name (remove version suffix like "-v20240930")
                let modelName = extractBaseModelName(rawName)
                foundModels.insert(modelName)
            }
            // Check for huggingface hub cache format
            else if name.contains("whisperkit-coreml") {
                // Look inside for model variants
                let snapshotsPath = url.appendingPathComponent("snapshots")
                if let snapshots = try? FileManager.default.contentsOfDirectory(at: snapshotsPath, includingPropertiesForKeys: nil) {
                    for snapshot in snapshots where snapshot.hasDirectoryPath {
                        if let modelDirs = try? FileManager.default.contentsOfDirectory(at: snapshot, includingPropertiesForKeys: nil) {
                            for modelDir in modelDirs where modelDir.hasDirectoryPath {
                                let dirName = modelDir.lastPathComponent
                                if dirName.starts(with: "openai_whisper-") {
                                    let rawName = String(dirName.dropFirst("openai_whisper-".count))
                                    foundModels.insert(extractBaseModelName(rawName))
                                }
                            }
                        }
                    }
                }
            }
            // Direct model name match
            else if WhisperModel.allCases.contains(where: { $0.rawValue == name }) {
                foundModels.insert(name)
            }
        }
    }

    private func extractBaseModelName(_ rawName: String) -> String {
        // Handle versioned names like "large-v3-v20240930" -> "large-v3" or "large-v3_turbo"
        // and simple names like "small.en" -> "small.en"

        // Check if it matches our known model names directly
        for model in WhisperModel.allCases {
            if rawName == model.rawValue || rawName.hasPrefix(model.rawValue + "-v") {
                return model.rawValue
            }
        }

        // Try to match base name patterns (order matters - more specific first)
        let patterns = [
            ("large-v3_turbo", "large-v3_turbo"),
            ("large-v3-turbo", "large-v3_turbo"),
            ("large-v3", "large-v3"),
            ("large-v2_turbo", "large-v2"),
            ("large-v2-turbo", "large-v2"),
            ("large-v2", "large-v2"),
            ("medium.en", "medium.en"),
            ("medium", "medium"),
            ("small.en", "small.en"),
            ("small", "small"),
            ("base.en", "base.en"),
            ("base", "base"),
            ("tiny.en", "tiny.en"),
            ("tiny", "tiny")
        ]

        for (pattern, result) in patterns {
            if rawName.hasPrefix(pattern) {
                return result
            }
        }

        return rawName
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
        appState.currentlyDownloadingModel = modelName
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
            appState.downloadedModels.insert(modelName)
            appState.isModelDownloaded = downloadedModels.contains(appState.whisperModel.rawValue)
            appState.isDownloadingModel = false
            appState.currentlyDownloadingModel = nil
            appState.modelDownloadProgress = 1.0

        } catch {
            appState.isDownloadingModel = false
            appState.currentlyDownloadingModel = nil
            appState.lastError = "Failed to download model: \(error.localizedDescription)"
            throw error
        }
    }

    func deleteModel(_ modelName: String) throws {
        let fileManager = FileManager.default
        var deleted = false

        // Check all possible locations where the model might be stored
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let homeDir = fileManager.homeDirectoryForCurrentUser

        let possiblePaths = [
            modelsDirectory.appendingPathComponent(modelName),
            modelsDirectory.appendingPathComponent("openai_whisper-\(modelName)"),
            appSupport.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-\(modelName)"),
            homeDir.appendingPathComponent(".cache/huggingface/hub/models--argmaxinc--whisperkit-coreml/snapshots")
        ]

        for path in possiblePaths {
            if path.lastPathComponent == "snapshots" {
                // Search in huggingface cache snapshots
                if let snapshots = try? fileManager.contentsOfDirectory(at: path, includingPropertiesForKeys: nil) {
                    for snapshot in snapshots where snapshot.hasDirectoryPath {
                        let modelDir = snapshot.appendingPathComponent("openai_whisper-\(modelName)")
                        if fileManager.fileExists(atPath: modelDir.path) {
                            try fileManager.removeItem(at: modelDir)
                            deleted = true
                        }
                    }
                }
            } else if fileManager.fileExists(atPath: path.path) {
                try fileManager.removeItem(at: path)
                deleted = true
            }
        }

        if deleted {
            downloadedModels.remove(modelName)
            appState.downloadedModels.remove(modelName)

            if modelName == appState.whisperModel.rawValue {
                appState.isModelDownloaded = false
            }
        }
    }

    func isModelDownloaded(_ modelName: String) -> Bool {
        return downloadedModels.contains(modelName)
    }

    func availableModels() -> [WhisperModel] {
        return WhisperModel.allCases
    }
}
