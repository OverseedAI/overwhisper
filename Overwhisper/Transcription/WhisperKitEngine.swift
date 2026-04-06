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

        // Get language, task, and vocabulary settings
        let language = await appState.language
        let shouldTranslate = await appState.translateToEnglish
        let customVocabulary = await appState.customVocabulary

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

        // Encode custom vocabulary as prompt tokens to bias spelling
        var promptTokens: [Int]?
        if !customVocabulary.isEmpty, let tokenizer = whisperKit.tokenizer {
            let promptText = " " + customVocabulary.trimmingCharacters(in: .whitespaces)
            promptTokens = tokenizer.encode(text: promptText)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            AppLogger.transcription.debug("Custom vocabulary prompt tokens: \(promptTokens?.count ?? 0) tokens")
        }

        // Get smart feature settings
        let autoPunctuation = await appState.autoPunctuation
        let profanityFilter = await appState.profanityFilter
        
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
            clipTimestamps: [],
            promptTokens: promptTokens
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
        
        var processedText = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        // Apply auto-punctuation if enabled
        if autoPunctuation {
            processedText = applyAutoPunctuation(to: processedText)
        }
        
        // Apply profanity filter if enabled
        if profanityFilter {
            processedText = applyProfanityFilter(to: processedText)
        }

        return processedText
    }
    
    private func applyAutoPunctuation(to text: String) -> String {
        // Simple auto-punctuation: capitalize first letter of sentences
        var result = text
        
        // Capitalize first letter
        if let firstChar = result.first {
            result = String(firstChar).uppercased() + result.dropFirst()
        }
        
        // Add period at end if no punctuation
        if let lastChar = result.last, !".!?".contains(lastChar) {
            result += "."
        }
        
        // Capitalize after sentence endings
        let sentenceEndings = [". ", "? ", "! "]
        for ending in sentenceEndings {
            result = result.replacingOccurrences(
                of: ending + "([a-z])",
                with: ending + "$1",
                options: .regularExpression,
                range: nil
            )
            // Actually capitalize
            var newResult = result
            for (index, char) in result.enumerated() {
                if index > 1 {
                    let prevIndex = result.index(result.startIndex, offsetBy: index - 2)
                    let prevPrevIndex = result.index(result.startIndex, offsetBy: index - 1)
                    let prevChars = String(result[prevIndex...prevPrevIndex])
                    if (prevChars == ". " || prevChars == "? " || prevChars == "! ") && char.isLowercase {
                        let charIndex = result.index(result.startIndex, offsetBy: index)
                        newResult.replaceSubrange(charIndex...charIndex, with: String(char).uppercased())
                    }
                }
            }
            result = newResult
        }
        
        return result
    }
    
    private func applyProfanityFilter(to text: String) -> String {
        // Common profanity words to mask
        let profanityList = [
            "damn", "hell", "crap", "stupid", "idiot"
            // Add more as needed - keeping it minimal for now
        ]
        
        var result = text
        for word in profanityList {
            let mask = String(repeating: "*", count: word.count)
            result = result.replacingOccurrences(
                of: "\\b\(word)\\b",
                with: mask,
                options: [.regularExpression, .caseInsensitive],
                range: nil
            )
        }
        return result
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
