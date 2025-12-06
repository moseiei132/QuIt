//
//  UpdateChecker.swift
//  QuIt
//
//  Created for update checking functionality
//

import Foundation
import AppKit
import Combine

struct AppUpdateInfo: Codable {
    let tagName: String
    let name: String
    let body: String
    let publishedAt: String
    let htmlURL: String
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case publishedAt = "published_at"
        case htmlURL = "html_url"
    }
    
    var version: String {
        // Remove 'v' prefix if present (e.g., "v1.0.0" → "1.0.0")
        return tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }
}

class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    
    // MARK: - Configuration
    private let updateURL = "https://api.github.com/repos/moseiei132/QuIt/releases/latest"
    private let releasesPageURL = "https://github.com/moseiei132/QuIt/releases"
    
    @Published var isCheckingForUpdates = false
    @Published var updateAvailable = false
    @Published var latestVersion: AppUpdateInfo?
    @Published var lastChecked: Date?
    
    private let lastCheckKey = "lastUpdateCheck"
    private let autoCheckKey = "autoCheckForUpdates"
    
    private init() {
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
                        self?.showErrorAlert(message: "Failed to check for updates: \(error.localizedDescription)")
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
            }
        } else if showAlert {
            showUpToDateAlert()
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
        alert.addButton(withTitle: "View on GitHub")
        alert.addButton(withTitle: "Later")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // View on GitHub button clicked
            if let url = URL(string: releasesPageURL) {
                NSWorkspace.shared.open(url)
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
        alert.messageText = "Update Check Failed"
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
            let daysSinceLastCheck = Calendar.current.dateComponents([.day], from: lastCheck, to: Date()).day ?? 0
            guard daysSinceLastCheck >= 1 else { return }
        }
        
        checkForUpdates(showAlert: false)
    }
}
