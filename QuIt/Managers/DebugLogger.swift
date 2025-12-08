//
//  DebugLogger.swift
//  QuIt
//
//  Debug logging manager with file logging support
//

import Combine
import Foundation

class DebugLogger: ObservableObject {
    static let shared = DebugLogger()

    @Published var isDebugEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isDebugEnabled, forKey: debugEnabledKey)
            log("Debug mode \(isDebugEnabled ? "enabled" : "disabled")", level: .info)
        }
    }

    private let debugEnabledKey = "debugModeEnabled"
    private let logFileName = "quit_debug.log"
    private let maxLogSize: Int64 = 10 * 1024 * 1024  // 10MB max log file size

    private var logFileURL: URL? {
        guard
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        else {
            return nil
        }

        let quItFolder = appSupport.appendingPathComponent("QuIt", isDirectory: true)

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: quItFolder, withIntermediateDirectories: true)

        return quItFolder.appendingPathComponent(logFileName)
    }

    enum LogLevel: String {
        case debug = "🔍 DEBUG"
        case info = "ℹ️ INFO"
        case warning = "⚠️ WARNING"
        case error = "❌ ERROR"
    }

    private init() {
        isDebugEnabled = UserDefaults.standard.bool(forKey: debugEnabledKey)
        log("DebugLogger initialized", level: .info)
    }

    func log(
        _ message: String, level: LogLevel = .debug, file: String = #file,
        function: String = #function, line: Int = #line
    ) {
        // Always print to console for errors and warnings
        if level == .error || level == .warning {
            print("\(level.rawValue): \(message)")
        }

        // Only log to file if debug mode is enabled
        guard isDebugEnabled else { return }

        let timestamp = DateFormatter.logTimestamp.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let logEntry =
            "[\(timestamp)] \(level.rawValue) [\(fileName):\(line)] \(function) - \(message)\n"

        // Print to console
        print(logEntry.trimmingCharacters(in: .newlines))

        // Write to file
        writeToFile(logEntry)
    }

    private func writeToFile(_ message: String) {
        guard let fileURL = logFileURL else { return }

        // Check file size and rotate if needed
        if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
            let fileSize = attributes[.size] as? Int64,
            fileSize > maxLogSize
        {
            rotateLog()
        }

        // Append to file
        if let data = message.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    private func rotateLog() {
        guard let fileURL = logFileURL else { return }

        let backupURL = fileURL.deletingPathExtension().appendingPathExtension("old.log")

        // Remove old backup
        try? FileManager.default.removeItem(at: backupURL)

        // Move current log to backup
        try? FileManager.default.moveItem(at: fileURL, to: backupURL)

        log("Log file rotated", level: .info)
    }

    func clearLogs() {
        guard let fileURL = logFileURL else { return }

        try? FileManager.default.removeItem(at: fileURL)

        let backupURL = fileURL.deletingPathExtension().appendingPathExtension("old.log")
        try? FileManager.default.removeItem(at: backupURL)

        log("Logs cleared", level: .info)
    }

    func getLogContent() -> String {
        guard let fileURL = logFileURL,
            let content = try? String(contentsOf: fileURL, encoding: .utf8)
        else {
            return "No logs available"
        }
        return content
    }

    func getLogFileURL() -> URL? {
        return logFileURL
    }

    func getLogFileSize() -> String {
        guard let fileURL = logFileURL,
            let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
            let fileSize = attributes[.size] as? Int64
        else {
            return "0 KB"
        }

        let sizeInKB = Double(fileSize) / 1024.0
        if sizeInKB < 1024 {
            return String(format: "%.1f KB", sizeInKB)
        } else {
            let sizeInMB = sizeInKB / 1024.0
            return String(format: "%.1f MB", sizeInMB)
        }
    }
}

// Date formatter extension for log timestamps
extension DateFormatter {
    static let logTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
}
