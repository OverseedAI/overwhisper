import Foundation

class CacheManager {
    static let shared = CacheManager()
    
    private let fileManager = FileManager.default
    private let tempDirectory = FileManager.default.temporaryDirectory
    
    // Maximum age for temp files (7 days)
    private let maxTempFileAge: TimeInterval = 7 * 24 * 60 * 60
    
    // Maximum cache size in MB
    private let maxCacheSizeMB: Int = 500
    
    private init() {}
    
    /// Cleans up old temporary files
    func cleanupTempFiles() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let files = try self.fileManager.contentsOfDirectory(
                    at: self.tempDirectory,
                    includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey]
                )
                
                let now = Date()
                var cleanedCount = 0
                
                for file in files {
                    // Only clean files with our prefixes
                    let filename = file.lastPathComponent
                    guard filename.hasPrefix("overwhisper_") || filename.hasPrefix("Overwhisper_") else {
                        continue
                    }
                    
                    do {
                        let attributes = try self.fileManager.attributesOfItem(atPath: file.path)
                        if let modificationDate = attributes[.modificationDate] as? Date {
                            let age = now.timeIntervalSince(modificationDate)
                            
                            if age > self.maxTempFileAge {
                                try self.fileManager.removeItem(at: file)
                                cleanedCount += 1
                                AppLogger.system.debug("Cleaned up old temp file: \(filename)")
                            }
                        }
                    } catch {
                        AppLogger.system.error("Failed to check/remove temp file: \(error.localizedDescription)")
                    }
                }
                
                if cleanedCount > 0 {
                    AppLogger.system.info("Cleaned up \(cleanedCount) old temporary files")
                }
            } catch {
                AppLogger.system.error("Failed to list temp directory: \(error.localizedDescription)")
            }
        }
    }
    
    /// Gets the total size of temporary files in MB
    func getTempFilesSizeMB() -> Int {
        do {
            let files = try fileManager.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: [.fileSizeKey])
            var totalSize: Int64 = 0
            
            for file in files {
                let attributes = try? fileManager.attributesOfItem(atPath: file.path)
                if let size = attributes?[.size] as? Int64 {
                    totalSize += size
                }
            }
            
            return Int(totalSize / (1024 * 1024))
        } catch {
            return 0
        }
    }
    
    /// Performs emergency cleanup if cache size exceeds limit
    func emergencyCleanupIfNeeded() {
        let currentSize = getTempFilesSizeMB()
        
        if currentSize > self.maxCacheSizeMB {
            AppLogger.system.warning("Cache size (\(currentSize)MB) exceeds limit (\(self.maxCacheSizeMB)MB), performing emergency cleanup")
            
            do {
                let files = try fileManager.contentsOfDirectory(
                    at: tempDirectory,
                    includingPropertiesForKeys: [.contentModificationDateKey]
                )
                
                // Sort by modification date (oldest first)
                let sortedFiles = files.compactMap { file -> (URL, Date)? in
                    guard let attributes = try? self.fileManager.attributesOfItem(atPath: file.path),
                          let date = attributes[.modificationDate] as? Date else {
                        return nil
                    }
                    return (file, date)
                }.sorted { $0.1 < $1.1 }
                
                // Remove oldest files until under limit
                var sizeToFree = currentSize - (self.maxCacheSizeMB / 2)  // Target 50% of limit
                
                for (file, _) in sortedFiles {
                    guard sizeToFree > 0 else { break }
                    
                    let filename = file.lastPathComponent
                    guard filename.hasPrefix("overwhisper_") || filename.hasPrefix("Overwhisper_") else {
                        continue
                    }
                    
                    do {
                        let attributes = try fileManager.attributesOfItem(atPath: file.path)
                        if let size = attributes[.size] as? Int64 {
                            try fileManager.removeItem(at: file)
                            sizeToFree -= Int(size / (1024 * 1024))
                            AppLogger.system.debug("Emergency cleanup removed: \(filename)")
                        }
                    } catch {
                        AppLogger.system.error("Failed to remove file during emergency cleanup: \(error.localizedDescription)")
                    }
                }
            } catch {
                AppLogger.system.error("Emergency cleanup failed: \(error.localizedDescription)")
            }
        }
    }
    
    /// Schedules periodic cache cleanup
    func schedulePeriodicCleanup() {
        // Clean up on launch
        cleanupTempFiles()
        
        // Schedule periodic cleanup every hour
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.cleanupTempFiles()
            self?.emergencyCleanupIfNeeded()
        }
    }
}

// MARK: - Crash Recovery

class CrashRecovery {
    static let shared = CrashRecovery()
    
    private let recoveryKey = "lastRecordingURL"
    private let recordingStartTimeKey = "lastRecordingStartTime"
    private let fileManager = FileManager.default
    
    private init() {}
    
    /// Records that a recording has started (for crash recovery)
    func recordRecordingStarted(url: URL) {
        UserDefaults.standard.set(url.path, forKey: recoveryKey)
        UserDefaults.standard.set(Date(), forKey: recordingStartTimeKey)
    }
    
    /// Records that a recording has ended (clears recovery data)
    func recordRecordingEnded() {
        UserDefaults.standard.removeObject(forKey: recoveryKey)
        UserDefaults.standard.removeObject(forKey: recordingStartTimeKey)
    }
    
    /// Checks if there was a recording in progress before a crash
    func checkForCrashedRecording() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: recoveryKey),
              let startTime = UserDefaults.standard.object(forKey: recordingStartTimeKey) as? Date else {
            return nil
        }
        
        let url = URL(fileURLWithPath: path)
        
        // Only recover if recording started within last 5 minutes
        // (prevents recovering very old/stale recordings)
        let timeSinceStart = Date().timeIntervalSince(startTime)
        guard timeSinceStart < 300 else {  // 5 minutes
            recordRecordingEnded()
            return nil
        }
        
        // Check if file exists and has content
        guard fileManager.fileExists(atPath: url.path) else {
            recordRecordingEnded()
            return nil
        }
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? Int64, size > 1024 {  // At least 1KB
                AppLogger.system.info("Found recoverable recording: \(url.lastPathComponent) (\(size) bytes)")
                return url
            }
        } catch {
            AppLogger.system.error("Failed to check crashed recording: \(error.localizedDescription)")
        }
        
        recordRecordingEnded()
        return nil
    }
    
    /// Attempts to recover a crashed recording
    func recoverCrashedRecording() async -> URL? {
        guard let url = checkForCrashedRecording() else { return nil }
        
        // Verify the file is still valid
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? Int64, size > 0 {
                AppLogger.system.info("Recovering recording: \(url.lastPathComponent)")
                recordRecordingEnded()
                return url
            }
        } catch {
            AppLogger.system.error("Failed to recover recording: \(error.localizedDescription)")
        }
        
        return nil
    }
}
