import Foundation
import CryptoKit
import WhisperKit

@MainActor
class ModelManager: ObservableObject {
    private let appState: AppState
    private let modelsDirectory: URL

    /// When running as a dev build (not a .app bundle), models are stored in <repo>/.models/
    let devDownloadBase: URL?

    @Published var downloadedModels: Set<String> = []
    @Published var downloadProgress: [String: Double] = [:]

    private static var isDevBuild: Bool {
        !Bundle.main.bundlePath.hasSuffix(".app")
    }

    init(appState: AppState) {
        self.appState = appState

        // Set up models directory in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.modelsDirectory = appSupport.appendingPathComponent("Overwhisper/Models", isDirectory: true)

        // For dev builds, use .models/ in the working directory (repo root)
        if Self.isDevBuild {
            let devDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".models", isDirectory: true)
            self.devDownloadBase = devDir
            try? FileManager.default.createDirectory(at: devDir, withIntermediateDirectories: true)
        } else {
            self.devDownloadBase = nil
        }

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

        // Dev build stores models in <repo>/.models/huggingface/models/argmaxinc/whisperkit-coreml/
        if let devBase = devDownloadBase {
            let devModelsPath = devBase.appendingPathComponent("models/argmaxinc/whisperkit-coreml")
            scanDirectory(devModelsPath, foundModels: &foundModels)
        }

        for basePath in possiblePaths {
            scanDirectory(basePath, foundModels: &foundModels)
        }

        AppLogger.transcription.info("Found models: \(foundModels)")

        downloadedModels = foundModels
        appState.downloadedModels = foundModels
        appState.isModelDownloaded = foundModels.contains(appState.whisperModel.variantName)
    }

    private func scanDirectory(_ path: URL, foundModels: inout Set<String>) {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: nil) else {
            return
        }

        for url in contents where url.hasDirectoryPath {
            let name = url.lastPathComponent

            if Self.isModelVariantFolder(name) {
                foundModels.insert(name)
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
                                if Self.isModelVariantFolder(dirName) {
                                    foundModels.insert(dirName)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Model folders are published as full variant names, e.g. `openai_whisper-small.en`,
    /// `openai_whisper-large-v3-v20240930_626MB` or `distil-whisper_distil-large-v3_turbo`.
    ///
    /// Previously these were collapsed to a coarse base name, which made every quantized and
    /// turbo build indistinguishable from its parent (`large-v3_947MB` was reported as
    /// `large-v3`). The full name is now preserved so each variant is tracked independently.
    nonisolated static func isModelVariantFolder(_ name: String) -> Bool {
        name.hasPrefix("openai_whisper-") || name.hasPrefix("distil-whisper_")
    }

    /// Exact-match a download folder against a model id.
    ///
    /// Matching must be exact rather than prefix-based: `openai_whisper-large-v3`,
    /// `openai_whisper-large-v3_947MB` and `openai_whisper-large-v3-v20240930` are three
    /// separate downloads, and a prefix match would delete or claim all three when the user
    /// asked about one. Legacy short ids ("large-v3") are accepted by canonicalizing first.
    nonisolated static func folderName(_ folderName: String, matches modelName: String) -> Bool {
        folderName == WhisperModel(rawValue: modelName).variantName
    }

    func getModelPath(for modelName: String) async throws -> String? {
        let modelPath = modelsDirectory.appendingPathComponent(modelName)

        if FileManager.default.fileExists(atPath: modelPath.path) {
            return modelPath.path
        }

        return nil
    }

    func downloadModel(_ modelName: String) async throws {
        // Always request the fully-qualified variant. WhisperKit globs the repo for the variant
        // string, so a bare name like "large-v3" matches several folders (`large-v3`,
        // `large-v3_947MB`, `large-v3-v20240930`, ...) and the download becomes ambiguous.
        let variant = WhisperModel(rawValue: modelName).variantName

        appState.isDownloadingModel = true
        appState.currentlyDownloadingModel = variant
        appState.modelDownloadProgress = 0

        do {
            // Use WhisperKit's built-in download functionality
            let modelFolder = try await WhisperKit.download(
                variant: variant,
                downloadBase: devDownloadBase,
                progressCallback: { progress in
                    Task { @MainActor in
                        self.appState.modelDownloadProgress = progress.fractionCompleted
                        self.downloadProgress[variant] = progress.fractionCompleted
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
            downloadedModels.insert(variant)
            appState.downloadedModels.insert(variant)
            appState.isModelDownloaded = downloadedModels.contains(appState.whisperModel.variantName)
            appState.isDownloadingModel = false
            appState.currentlyDownloadingModel = nil
            appState.modelDownloadProgress = 1.0
            UsageAnalytics.trackModelDownload(engine: .whisperKit, model: variant, succeeded: true)

        } catch {
            appState.isDownloadingModel = false
            appState.currentlyDownloadingModel = nil
            if let validationError = error as? ModelDownloadError {
                appState.lastError = validationError.localizedDescription
            } else {
                appState.lastError = "Failed to download model: \(error.localizedDescription)"
            }
            UsageAnalytics.trackModelDownload(engine: .whisperKit, model: variant, succeeded: false)
            throw error
        }
    }

    func deleteModel(_ modelName: String) throws {
        let fileManager = FileManager.default
        var deleted = false

        // Check all possible locations where the model might be stored
        // Must match the same paths as scanForModels()
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let homeDir = fileManager.homeDirectoryForCurrentUser

        let searchPaths = [
            // MacWhisper's model directory
            appSupport.appendingPathComponent("MacWhisper/models/whisperkit/models/argmaxinc/whisperkit-coreml"),
            // SuperWhisper's model directory
            appSupport.appendingPathComponent("superwhisper/models/argmaxinc/whisperkit-coreml"),
            // Huggingface in Documents
            homeDir.appendingPathComponent("Documents/huggingface/models/argmaxinc/whisperkit-coreml"),
            // Standard huggingface cache in Application Support
            appSupport.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml"),
            // Our custom directory
            modelsDirectory
        ]

        // Search direct paths for model folders (with potential version suffixes)
        for basePath in searchPaths {
            guard let contents = try? fileManager.contentsOfDirectory(at: basePath, includingPropertiesForKeys: nil) else {
                continue
            }

            for url in contents where url.hasDirectoryPath {
                let name = url.lastPathComponent
                if Self.folderName(name, matches: modelName) {
                    try fileManager.removeItem(at: url)
                    deleted = true
                    AppLogger.transcription.info("Deleted model at: \(url.path)")
                }
            }
        }

        // Also check huggingface hub cache structure
        let hubCachePath = homeDir.appendingPathComponent(".cache/huggingface/hub/models--argmaxinc--whisperkit-coreml/snapshots")
        if let snapshots = try? fileManager.contentsOfDirectory(at: hubCachePath, includingPropertiesForKeys: nil) {
            for snapshot in snapshots where snapshot.hasDirectoryPath {
                if let modelDirs = try? fileManager.contentsOfDirectory(at: snapshot, includingPropertiesForKeys: nil) {
                    for modelDir in modelDirs where modelDir.hasDirectoryPath {
                        let name = modelDir.lastPathComponent
                        if Self.folderName(name, matches: modelName) {
                            try fileManager.removeItem(at: modelDir)
                            deleted = true
                            AppLogger.transcription.info("Deleted model at: \(modelDir.path)")
                        }
                    }
                }
            }
        }

        if deleted {
            let variant = WhisperModel(rawValue: modelName).variantName
            downloadedModels.remove(variant)
            appState.downloadedModels.remove(variant)

            if variant == appState.whisperModel.variantName {
                appState.isModelDownloaded = false
            }
        } else {
            AppLogger.transcription.warning("No model files found to delete for: \(modelName)")
        }
    }

    func isModelDownloaded(_ modelName: String) -> Bool {
        return downloadedModels.contains(WhisperModel(rawValue: modelName).variantName)
    }

    /// Returns the on-disk folder path for a cached model, or nil if not found.
    func findModelFolder(for modelName: String) -> String? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let homeDir = FileManager.default.homeDirectoryForCurrentUser

        var possiblePaths = [
            appSupport.appendingPathComponent("MacWhisper/models/whisperkit/models/argmaxinc/whisperkit-coreml"),
            appSupport.appendingPathComponent("superwhisper/models/argmaxinc/whisperkit-coreml"),
            homeDir.appendingPathComponent("Documents/huggingface/models/argmaxinc/whisperkit-coreml"),
            appSupport.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml"),
            modelsDirectory
        ]
        if let devBase = devDownloadBase {
            possiblePaths.append(devBase.appendingPathComponent("models/argmaxinc/whisperkit-coreml"))
        }

        // Check direct paths (e.g. .../openai_whisper-small.en/)
        for basePath in possiblePaths {
            guard let contents = try? FileManager.default.contentsOfDirectory(at: basePath, includingPropertiesForKeys: nil) else { continue }
            for url in contents where url.hasDirectoryPath {
                if Self.folderName(url.lastPathComponent, matches: modelName) {
                    return url.path
                }
            }
        }

        // Check huggingface hub cache (snapshots)
        let hubCachePath = homeDir.appendingPathComponent(".cache/huggingface/hub")
        if let repoDirs = try? FileManager.default.contentsOfDirectory(at: hubCachePath, includingPropertiesForKeys: nil) {
            for repoDir in repoDirs where repoDir.lastPathComponent.contains("whisperkit-coreml") {
                let snapshotsPath = repoDir.appendingPathComponent("snapshots")
                if let snapshots = try? FileManager.default.contentsOfDirectory(at: snapshotsPath, includingPropertiesForKeys: nil) {
                    for snapshot in snapshots where snapshot.hasDirectoryPath {
                        if let modelDirs = try? FileManager.default.contentsOfDirectory(at: snapshot, includingPropertiesForKeys: nil) {
                            for modelDir in modelDirs where modelDir.hasDirectoryPath {
                                if Self.folderName(modelDir.lastPathComponent, matches: modelName) {
                                    return modelDir.path
                                }
                            }
                        }
                    }
                }
            }
        }

        return nil
    }

    func availableModels() -> [WhisperModel] {
        return WhisperModelCatalog.shared.models
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
