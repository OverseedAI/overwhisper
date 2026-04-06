import Foundation
import Darwin

struct SystemInfo {
    /// Get total physical memory in GB
    static func getTotalMemoryGB() -> Double {
        var size: UInt64 = 0
        var sizeLength = MemoryLayout<UInt64>.size
        
        let result = sysctlbyname("hw.memsize", &size, &sizeLength, nil, 0)
        guard result == 0 else { return 8 } // Default to 8GB if unable to get
        
        return Double(size) / (1024 * 1024 * 1024)
    }
    
    /// Get available storage space in GB
    static func getAvailableStorageGB() -> Double {
        do {
            let fileURL = URL(fileURLWithPath: NSHomeDirectory())
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            if let capacity = values.volumeAvailableCapacity {
                return Double(capacity) / (1024 * 1024 * 1024)
            }
        } catch {
            print("Error getting storage: \(error)")
        }
        return 10 // Default to 10GB if unable to get
    }
    
    /// Get the number of CPU cores
    static func getCPUCoreCount() -> Int {
        var coreCount: Int32 = 0
        var size = MemoryLayout<Int32>.size
        
        let result = sysctlbyname("hw.ncpu", &coreCount, &size, nil, 0)
        guard result == 0 else { return 4 } // Default to 4 cores
        
        return Int(coreCount)
    }
    
    /// Check if Mac has Apple Silicon
    static func isAppleSilicon() -> Bool {
        var brandString = [CChar](repeating: 0, count: 128)
        var size = brandString.count
        let result = sysctlbyname("machdep.cpu.brand_string", &brandString, &size, nil, 0)
        
        guard result == 0 else { return false }
        
        let processor = String(cString: brandString)
        return processor.contains("Apple") && !processor.contains("Intel")
    }
    
    /// Determine the recommended model based on system specs
    static func getRecommendedModel() -> WhisperModel {
        let memoryGB = getTotalMemoryGB()
        let storageGB = getAvailableStorageGB()
        let isAppleSilicon = isAppleSilicon()
        
        print("System Info:")
        print("  Memory: \(Int(memoryGB)) GB")
        print("  Available Storage: \(Int(storageGB)) GB")
        print("  Apple Silicon: \(isAppleSilicon)")
        
        // Decision logic based on system specs
        
        // Large models require significant RAM and storage
        if memoryGB >= 16 && storageGB >= 4 {
            // High-end Mac - can handle large models
            if isAppleSilicon {
                // Apple Silicon handles large models better
                return .largeV3Turbo
            } else {
                return .largeV3
            }
        }
        
        // Medium models need at least 8GB RAM and 2GB storage
        if memoryGB >= 8 && storageGB >= 2 {
            return .mediumEn
        }
        
        // Small models work on most modern Macs
        if memoryGB >= 4 && storageGB >= 1 {
            return .smallEn
        }
        
        // Base model for very constrained systems
        if memoryGB >= 2 && storageGB >= 0.5 {
            return .baseEn
        }
        
        // Tiny as last resort
        return .tinyEn
    }
    
    /// Get a human-readable description of the system
    static func getSystemDescription() -> String {
        let memory = Int(getTotalMemoryGB())
        let storage = Int(getAvailableStorageGB())
        let chip = isAppleSilicon() ? "Apple Silicon" : "Intel"
        
        return "\(chip) • \(memory) GB RAM • \(storage) GB available"
    }
}

// Model size requirements for reference
extension WhisperModel {
    /// Approximate RAM required to run this model (in GB)
    var ramRequirementGB: Double {
        switch self {
        case .tiny, .tinyEn:
            return 1
        case .base, .baseEn:
            return 1.5
        case .small, .smallEn:
            return 2
        case .medium, .mediumEn:
            return 4
        case .largeV2, .largeV3:
            return 6
        case .largeV3Turbo:
            return 4
        }
    }
    
    /// Whether this model is recommended for the current system
    func isRecommendedForSystem() -> Bool {
        return SystemInfo.getRecommendedModel() == self
    }
}
