import Foundation

/// Simple local crash reporter that logs crashes to ~/Library/Logs/Overwhisper/
final class CrashReporter {
    static let shared = CrashReporter()

    private let logDirectory: URL
    private let logFile: URL
    private let maxLogSizeBytes: Int = 1_000_000 // 1 MB max log size

    private init() {
        let libraryLogs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs")
            .appendingPathComponent("Overwhisper")

        self.logDirectory = libraryLogs
        self.logFile = libraryLogs.appendingPathComponent("crash.log")

        // Create directory if needed
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    /// Install crash handlers - call this early in app launch
    func install() {
        // Set up uncaught exception handler
        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.shared.logException(exception)
        }

        // Set up signal handlers for common crash signals
        setupSignalHandler(SIGABRT)
        setupSignalHandler(SIGILL)
        setupSignalHandler(SIGSEGV)
        setupSignalHandler(SIGFPE)
        setupSignalHandler(SIGBUS)
        setupSignalHandler(SIGTRAP)

        log("Crash reporter installed")
    }

    private func setupSignalHandler(_ signal: Int32) {
        Foundation.signal(signal) { sig in
            CrashReporter.shared.logSignal(sig)
            // Re-raise the signal to let the system handle it normally
            Foundation.signal(sig, SIG_DFL)
            raise(sig)
        }
    }

    /// Log a message to the crash log
    func log(_ message: String, source: String = "App") {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logLine = "[\(timestamp)] [\(source)] \(message)\n"

        appendToLog(logLine)
    }

    /// Log an uncaught exception
    private func logException(_ exception: NSException) {
        let logContent = """
        ================================================================================
        UNCAUGHT EXCEPTION
        Time: \(ISO8601DateFormatter().string(from: Date()))
        Name: \(exception.name.rawValue)
        Reason: \(exception.reason ?? "Unknown")

        Call Stack:
        \(exception.callStackSymbols.joined(separator: "\n"))
        ================================================================================

        """

        appendToLog(logContent)

        // Also log to stderr for immediate visibility
        fputs(logContent, stderr)
    }

    /// Log a signal crash
    private func logSignal(_ signal: Int32) {
        let signalName: String
        switch signal {
        case SIGABRT: signalName = "SIGABRT (Abort)"
        case SIGILL: signalName = "SIGILL (Illegal instruction)"
        case SIGSEGV: signalName = "SIGSEGV (Segmentation fault)"
        case SIGFPE: signalName = "SIGFPE (Floating point exception)"
        case SIGBUS: signalName = "SIGBUS (Bus error)"
        case SIGTRAP: signalName = "SIGTRAP (Trace trap)"
        default: signalName = "Signal \(signal)"
        }

        // Get stack trace
        var callStack = [String]()
        for symbol in Thread.callStackSymbols {
            callStack.append(symbol)
        }

        let logContent = """
        ================================================================================
        SIGNAL CRASH
        Time: \(ISO8601DateFormatter().string(from: Date()))
        Signal: \(signalName)

        Call Stack:
        \(callStack.joined(separator: "\n"))
        ================================================================================

        """

        // Write synchronously since we're crashing
        appendToLogSync(logContent)

        // Also log to stderr
        fputs(logContent, stderr)
    }

    private func appendToLog(_ content: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.appendToLogSync(content)
        }
    }

    private func appendToLogSync(_ content: String) {
        rotateLogIfNeeded()

        guard let data = content.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: logFile.path) {
            if let fileHandle = try? FileHandle(forWritingTo: logFile) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            try? data.write(to: logFile, options: .atomic)
        }
    }

    private func rotateLogIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFile.path),
              let fileSize = attrs[.size] as? Int,
              fileSize > maxLogSizeBytes else {
            return
        }

        // Rotate: rename current to .old, start fresh
        let oldLog = logDirectory.appendingPathComponent("crash.old.log")
        try? FileManager.default.removeItem(at: oldLog)
        try? FileManager.default.moveItem(at: logFile, to: oldLog)
    }

    /// Get the path to the crash log for user reference
    var logPath: String {
        return logFile.path
    }
}
