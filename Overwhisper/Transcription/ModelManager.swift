import Foundation
import CryptoKit
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

        AppLogger.transcription.info("Found models: \(foundModels)")

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
            let modelFolder = try await WhisperKit.download(
                variant: modelName,
                progressCallback: { progress in
                    Task { @MainActor in
                        self.appState.modelDownloadProgress = progress.fractionCompleted
                        self.downloadProgress[modelName] = progress.fractionCompleted
                    }
                }
            )

            do {
                try validateModelChecksum(at: modelFolder)
            } catch {
                try? FileManager.default.removeItem(at: modelFolder)
                throw error
            }

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
            if let validationError = error as? ModelDownloadError {
                appState.lastError = validationError.localizedDescription
            } else {
                appState.lastError = "Failed to download model: \(error.localizedDescription)"
            }
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

    private func validateModelChecksum(at modelFolder: URL) throws {
        let repoRoot = modelFolder.deletingLastPathComponent()
        let metadataRoot = repoRoot
            .appendingPathComponent(".cache")
            .appendingPathComponent("huggingface")
            .appendingPathComponent("download")

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: modelFolder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ModelDownloadError.validationFailed("Unable to enumerate model files for checksum validation.")
        }

        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues.isDirectory == true { continue }

            let repoPath = repoRoot.path.hasSuffix("/") ? repoRoot.path : repoRoot.path + "/"
            guard fileURL.path.hasPrefix(repoPath) else { continue }
            let relativePath = String(fileURL.path.dropFirst(repoPath.count))

            let metadataPath = metadataRoot.appendingPathComponent(relativePath + ".metadata")
            guard fileManager.fileExists(atPath: metadataPath.path) else {
                throw ModelDownloadError.missingMetadata(relativePath)
            }

            let metadata = try readDownloadMetadata(at: metadataPath)
            if isSha256(metadata.etag) {
                let fileHash = try computeFileHash(file: fileURL)
                if fileHash != metadata.etag {
                    throw ModelDownloadError.checksumMismatch(relativePath)
                }
            }
        }
    }

    private func readDownloadMetadata(at url: URL) throws -> DownloadMetadata {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.components(separatedBy: .newlines)
        guard lines.count >= 2 else {
            throw ModelDownloadError.invalidMetadata(url.lastPathComponent)
        }

        let commitHash = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let etag = lines[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !etag.isEmpty else {
            throw ModelDownloadError.invalidMetadata(url.lastPathComponent)
        }

        return DownloadMetadata(commitHash: commitHash, etag: etag)
    }

    private func isSha256(_ value: String) -> Bool {
        let pattern = "^[0-9a-f]{64}$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private func computeFileHash(file url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 1024 * 1024

        while autoreleasepool(invoking: {
            let data = try? handle.read(upToCount: chunkSize)
            guard let data, !data.isEmpty else { return false }
            hasher.update(data: data)
            return true
        }) {}

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private struct DownloadMetadata {
    let commitHash: String
    let etag: String
}

enum ModelDownloadError: LocalizedError {
    case missingMetadata(String)
    case invalidMetadata(String)
    case checksumMismatch(String)
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingMetadata(let file):
            return "Model download validation failed (missing metadata for \(file)). Please re-download."
        case .invalidMetadata(let file):
            return "Model download validation failed (invalid metadata for \(file)). Please re-download."
        case .checksumMismatch(let file):
            return "Model download validation failed (checksum mismatch for \(file)). Please re-download."
        case .validationFailed(let message):
            return "Model download validation failed. \(message)"
        }
    }
}
