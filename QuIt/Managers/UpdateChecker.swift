//
//  UpdateChecker.swift
//  QuIt
//
//  Created for update checking functionality
//

import AppKit
import Combine
import Foundation

// MARK: - Models

struct AppUpdateInfo: Codable {
    let tagName: String
    let name: String
    let body: String
    let publishedAt: String
    let htmlURL: String
    let assets: [ReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case publishedAt = "published_at"
        case htmlURL = "html_url"
        case assets
    }

    var version: String {
        // Remove 'v' prefix if present (e.g., "v1.0.0" → "1.0.0")
        return tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    var downloadURL: URL? {
        // Find the .zip asset
        guard
            let zipAsset = assets.first(where: {
                $0.name.hasSuffix(".zip") || $0.name.hasSuffix(".app.zip")
            })
        else {
            return nil
        }
        return URL(string: zipAsset.browserDownloadURL)
    }
}

struct ReleaseAsset: Codable {
    let name: String
    let browserDownloadURL: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
    }
}

// MARK: - Update Checker

class UpdateChecker: NSObject, ObservableObject {
    static let shared = UpdateChecker()

    // MARK: - Build Info

    enum BuildInfo {
        /// Returns true if the app was built with the OFFICIAL_BUILD flag (e.g. in CI/CD)
        static var isOfficialBuild: Bool {
            #if OFFICIAL_BUILD
                return true
            #else
                return false
            #endif
        }
    }

    // MARK: - Configuration
    private let updateURL = "https://api.github.com/repos/moseiei132/QuIt/releases/latest"
    private let releasesPageURL = "https://github.com/moseiei132/QuIt/releases"

    @Published var isCheckingForUpdates = false
    @Published var updateAvailable = false
    @Published var latestVersion: AppUpdateInfo?
    @Published var lastChecked: Date?

    // Download state
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0

    private let lastCheckKey = "lastUpdateCheck"
    private let autoCheckKey = "autoCheckForUpdates"
    private let autoDownloadKey = "autoDownloadUpdates"

    private var downloadTask: URLSessionDownloadTask?
    private var downloadedFileURL: URL?
    private var progressWindow: NSWindow?

    private override init() {
        super.init()
        loadSettings()
    }

    // MARK: - Settings

    var autoCheckEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: autoCheckKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: autoCheckKey)
        }
    }

    var autoDownloadEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: autoDownloadKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: autoDownloadKey)
        }
    }

    private func loadSettings() {
        if let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date {
            lastChecked = lastCheck
        }
    }

    private func saveLastCheckDate() {
        let now = Date()
        lastChecked = now
        UserDefaults.standard.set(now, forKey: lastCheckKey)
    }

    // MARK: - Version Comparison

    func getCurrentVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    func getCurrentBuildNumber() -> String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private func isNewerVersion(_ remoteVersion: String, than currentVersion: String) -> Bool {
        let remote = remoteVersion.split(separator: ".").compactMap { Int($0) }
        let current = currentVersion.split(separator: ".").compactMap { Int($0) }

        for (remoteComponent, currentComponent) in zip(remote, current) {
            if remoteComponent > currentComponent {
                return true
            } else if remoteComponent < currentComponent {
                return false
            }
        }

        // If all components are equal, check length
        return remote.count > current.count
    }

    // MARK: - Update Check

    func checkForUpdates(showAlert: Bool = true) {
        guard !isCheckingForUpdates else { return }

        isCheckingForUpdates = true
        updateAvailable = false

        print("🔍 Checking for updates...")

        guard let url = URL(string: updateURL) else {
            print("❌ Invalid update URL")
            isCheckingForUpdates = false
            return
        }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isCheckingForUpdates = false
                self?.saveLastCheckDate()

                if let error = error {
                    print("❌ Update check failed: \(error.localizedDescription)")
                    if showAlert {
                        self?.showErrorAlert(
                            message: "Failed to check for updates: \(error.localizedDescription)")
                    }
                    return
                }

                guard let data = data else {
                    print("❌ No data received")
                    if showAlert {
                        self?.showErrorAlert(message: "No update information received")
                    }
                    return
                }

                do {
                    let updateInfo = try JSONDecoder().decode(AppUpdateInfo.self, from: data)
                    self?.handleUpdateInfo(updateInfo, showAlert: showAlert)
                } catch {
                    print("❌ Failed to decode update info: \(error)")
                    if showAlert {
                        self?.showErrorAlert(message: "Failed to parse update information")
                    }
                }
            }
        }

        task.resume()
    }

    private func handleUpdateInfo(_ updateInfo: AppUpdateInfo, showAlert: Bool) {
        latestVersion = updateInfo

        let currentVersion = getCurrentVersion()
        let isNewer = isNewerVersion(updateInfo.version, than: currentVersion)

        updateAvailable = isNewer

        print("📦 Current version: \(currentVersion)")
        print("📦 Latest version: \(updateInfo.version)")
        print(isNewer ? "✅ Update available!" : "✅ You're up to date!")

        if isNewer {
            if showAlert {
                showUpdateAlert(updateInfo: updateInfo)
            } else if autoDownloadEnabled && BuildInfo.isOfficialBuild {
                // Auto-download in background if enabled
                downloadLatestVersion()
            }
        } else if showAlert {
            showUpToDateAlert()
        }
    }

    // MARK: - Download

    func downloadLatestVersion() {
        guard let updateInfo = latestVersion,
            let downloadURL = updateInfo.downloadURL
        else {
            showErrorAlert(message: "No download URL found in release")
            return
        }

        guard !isDownloading else { return }

        isDownloading = true
        downloadProgress = 0.0
        downloadedBytes = 0
        totalBytes = 0

        print("📥 Starting download from: \(downloadURL)")

        let configuration = URLSessionConfiguration.default
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

        downloadTask = session.downloadTask(with: downloadURL)
        downloadTask?.resume()

        // Show progress window
        DispatchQueue.main.async {
            self.showDownloadProgress()
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        isDownloading = false
        downloadProgress = 0.0
        progressWindow?.close()
        progressWindow = nil
        print("❌ Download cancelled")
    }

    private func showDownloadProgress() {
        guard progressWindow == nil else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 170),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Downloading Update"
        window.center()
        window.isReleasedWhenClosed = false

        let contentView = NSView(frame: window.contentView!.bounds)

        let label = NSTextField(labelWithString: "Downloading QuIt update...")
        label.frame = NSRect(x: 20, y: 130, width: 360, height: 20)
        label.alignment = .center

        let progressIndicator = NSProgressIndicator(
            frame: NSRect(x: 20, y: 100, width: 360, height: 20))
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.doubleValue = 0

        let statusLabel = NSTextField(labelWithString: "0 MB / 0 MB")
        statusLabel.frame = NSRect(x: 20, y: 70, width: 360, height: 20)
        statusLabel.alignment = .center

        let cancelButton = NSButton(frame: NSRect(x: 150, y: 20, width: 100, height: 30))
        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelDownloadAction)

        contentView.addSubview(label)
        contentView.addSubview(progressIndicator)
        contentView.addSubview(statusLabel)
        contentView.addSubview(cancelButton)

        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)

        self.progressWindow = window

        // Update progress periodically
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self, self.isDownloading else {
                timer.invalidate()
                return
            }

            progressIndicator.doubleValue = self.downloadProgress

            let downloadedMB = Double(self.downloadedBytes) / 1024.0 / 1024.0
            let totalMB = Double(self.totalBytes) / 1024.0 / 1024.0

            if totalMB > 0 {
                statusLabel.stringValue = String(
                    format: "%.1f MB / %.1f MB (%.0f%%)", downloadedMB, totalMB,
                    self.downloadProgress * 100)
            } else {
                statusLabel.stringValue = String(format: "%.1f MB", downloadedMB)
            }
        }
    }

    @objc private func cancelDownloadAction() {
        cancelDownload()
    }

    // MARK: - Installation

    private func installDownloadedUpdate(from fileURL: URL) {
        print("📦 Installing update from: \(fileURL)")

        do {
            // Create temporary directory for extraction
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // Unzip the downloaded file
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/unzip")
            process.arguments = ["-q", fileURL.path, "-d", tempDir.path]

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw NSError(
                    domain: "UpdateChecker", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to extract update"])
            }

            // Find the .app bundle
            let contents = try FileManager.default.contentsOfDirectory(
                at: tempDir, includingPropertiesForKeys: nil)
            guard let newAppURL = contents.first(where: { $0.pathExtension == "app" }) else {
                throw NSError(
                    domain: "UpdateChecker", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "No .app bundle found in update"])
            }

            // Get current app bundle path
            guard let currentAppURL = Bundle.main.bundleURL as URL? else {
                throw NSError(
                    domain: "UpdateChecker", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Could not locate current app"])
            }

            print("📦 Current app: \(currentAppURL.path)")
            print("📦 New app: \(newAppURL.path)")

            // Show confirmation dialog
            DispatchQueue.main.async {
                self.showInstallConfirmation(
                    newAppURL: newAppURL,
                    currentAppURL: currentAppURL,
                    tempDir: tempDir,
                    downloadedZipURL: fileURL
                )
            }

        } catch {
            DispatchQueue.main.async {
                self.showErrorAlert(
                    message: "Failed to install update: \(error.localizedDescription)")
            }
        }
    }

    private func showInstallConfirmation(
        newAppURL: URL, currentAppURL: URL, tempDir: URL, downloadedZipURL: URL
    ) {
        let alert = NSAlert()
        alert.messageText = "Ready to Install"
        alert.informativeText =
            "The update has been downloaded and is ready to install. QuIt will quit and relaunch with the new version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install & Relaunch")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            performInstallation(
                newAppURL: newAppURL,
                currentAppURL: currentAppURL,
                tempDir: tempDir,
                downloadedZipURL: downloadedZipURL
            )
        } else {
            // Clean up if user cancels
            cleanupUpdateFiles(tempDir: tempDir, downloadedZipURL: downloadedZipURL)
        }
    }

    private func performInstallation(
        newAppURL: URL, currentAppURL: URL, tempDir: URL, downloadedZipURL: URL
    ) {
        // Create a script to replace the app, clean up temporary files, and relaunch
        let script = """
            #!/bin/bash
            sleep 1
            # Replace the old app with the new one
            rm -rf "\(currentAppURL.path)"
            cp -R "\(newAppURL.path)" "\(currentAppURL.path)"
            # Clean up temporary files
            rm -rf "\(tempDir.path)"
            rm -f "\(downloadedZipURL.path)"
            rm -f "$0"
            # Relaunch the app
            open "\(currentAppURL.path)"
            """

        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "update_\(UUID().uuidString).sh")

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)

            // Make script executable
            let chmodProcess = Process()
            chmodProcess.executableURL = URL(filePath: "/bin/chmod")
            chmodProcess.arguments = ["+x", scriptURL.path]
            try chmodProcess.run()
            chmodProcess.waitUntilExit()

            print("🧹 Cleanup script will remove:")
            print("   - Temp directory: \(tempDir.path)")
            print("   - Downloaded ZIP: \(downloadedZipURL.path)")
            print("   - Update script: \(scriptURL.path)")

            // Execute script in background
            let process = Process()
            process.executableURL = URL(filePath: "/bin/bash")
            process.arguments = [scriptURL.path]
            try process.run()

            // Quit the app
            NSApplication.shared.terminate(nil)

        } catch {
            showErrorAlert(message: "Failed to perform installation: \(error.localizedDescription)")
            // Clean up on error, including the script file
            cleanupUpdateFiles(
                tempDir: tempDir, downloadedZipURL: downloadedZipURL, scriptURL: scriptURL)
        }
    }

    private func cleanupUpdateFiles(tempDir: URL, downloadedZipURL: URL, scriptURL: URL? = nil) {
        do {
            // Remove temporary extraction directory
            if FileManager.default.fileExists(atPath: tempDir.path) {
                try FileManager.default.removeItem(at: tempDir)
                print("🧹 Cleaned up temp directory: \(tempDir.path)")
            }

            // Remove downloaded ZIP file
            if FileManager.default.fileExists(atPath: downloadedZipURL.path) {
                try FileManager.default.removeItem(at: downloadedZipURL)
                print("🧹 Cleaned up downloaded ZIP: \(downloadedZipURL.path)")
            }

            // Remove update script file if it exists
            if let scriptURL = scriptURL, FileManager.default.fileExists(atPath: scriptURL.path) {
                try FileManager.default.removeItem(at: scriptURL)
                print("🧹 Cleaned up update script: \(scriptURL.path)")
            }
        } catch {
            print("⚠️ Failed to clean up update files: \(error.localizedDescription)")
        }
    }

    // MARK: - Alerts

    private func showUpdateAlert(updateInfo: AppUpdateInfo) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = """
            A new version of QuIt is available!

            Current Version: \(getCurrentVersion())
            Latest Version: \(updateInfo.version)

            Release Notes:
            \(updateInfo.body.isEmpty ? "See GitHub releases page for details" : updateInfo.body)
            """
        alert.alertStyle = .informational
        if BuildInfo.isOfficialBuild {
            alert.addButton(withTitle: "Download & Install")
            alert.addButton(withTitle: "View on GitHub")
            alert.addButton(withTitle: "Later")
        } else {
            alert.addButton(withTitle: "View on GitHub")
            alert.addButton(withTitle: "Later")
        }

        let response = alert.runModal()

        if BuildInfo.isOfficialBuild {
            if response == .alertFirstButtonReturn {
                // Download & Install
                downloadLatestVersion()
            } else if response == .alertSecondButtonReturn {
                // View on GitHub
                if let url = URL(string: releasesPageURL) {
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            if response == .alertFirstButtonReturn {
                // View on GitHub
                if let url = URL(string: releasesPageURL) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "QuIt \(getCurrentVersion()) is the latest version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Update Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Auto Check

    func performAutoCheckIfNeeded() {
        guard autoCheckEnabled else { return }

        // Check once per day
        if let lastCheck = lastChecked {
            let daysSinceLastCheck =
                Calendar.current.dateComponents([.day], from: lastCheck, to: Date()).day ?? 0
            guard daysSinceLastCheck >= 1 else { return }
        }

        checkForUpdates(showAlert: false)
    }
}

// MARK: - URLSessionDownloadDelegate

extension UpdateChecker: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        print("✅ Download completed: \(location)")

        // Move to a permanent location
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "QuIt_Update.zip")

        do {
            // Remove existing file if present
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try FileManager.default.moveItem(at: location, to: destinationURL)
            downloadedFileURL = destinationURL

            DispatchQueue.main.async {
                self.isDownloading = false
                self.progressWindow?.close()
                self.progressWindow = nil

                // Start installation
                self.installDownloadedUpdate(from: destinationURL)
            }
        } catch {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.showErrorAlert(
                    message: "Failed to save downloaded update: \(error.localizedDescription)")
            }
        }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        DispatchQueue.main.async {
            self.downloadedBytes = totalBytesWritten
            self.totalBytes = totalBytesExpectedToWrite

            if totalBytesExpectedToWrite > 0 {
                self.downloadProgress =
                    Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)
    {
        if let error = error {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.progressWindow?.close()
                self.progressWindow = nil

                if (error as NSError).code != NSURLErrorCancelled {
                    self.showErrorAlert(message: "Download failed: \(error.localizedDescription)")
                }
            }
        }
    }
}
