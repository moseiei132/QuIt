//
//  RunningAppsModel.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import AppKit
import Combine
import Foundation

// ViewModel to observe running apps and selection state
@MainActor
final class RunningAppsModel: ObservableObject {
    @Published var apps: [RunningApp] = []
    @Published var selectedIDs: Set<Int> = []

    private func isForceQuitEligible(_ app: NSRunningApplication) -> Bool {
        // Emulate Force Quit Applications list:
        // - Only user apps with a normal UI (activationPolicy == .regular)
        // - Exclude accessory/prohibited/background-only
        guard app.activationPolicy == .regular else { return false }
        // Optional: skip apps that haven't finished launching to avoid transient entries
        guard app.isFinishedLaunching else { return false }

        // Extra safety: exclude LSUIElement/LSBackgroundOnly if we can detect them
        if let bundleURL = app.bundleURL,
            let bundle = Bundle(url: bundleURL),
            let info = bundle.infoDictionary
        {
            if let isUIElement = info["LSUIElement"] as? Bool, isUIElement { return false }
            if let isBackgroundOnly = info["LSBackgroundOnly"] as? Bool, isBackgroundOnly {
                return false
            }
        }

        return true
    }

    func reload() {
        let currentPID = NSRunningApplication.current.processIdentifier
        let focusTracker = AppFocusTracker.shared

        let running = NSWorkspace.shared.runningApplications
            .filter {
                isForceQuitEligible($0) && $0.processIdentifier != currentPID
            }
            .map { app -> RunningApp in
                let pid = app.processIdentifier
                let id = Int(pid)  // unique per process
                let name = app.localizedName ?? app.bundleIdentifier ?? "PID \(pid)"
                let lastFocusTime = focusTracker.getLastFocusTime(for: app.bundleIdentifier)

                return RunningApp(
                    id: id,
                    bundleIdentifier: app.bundleIdentifier,
                    name: name,
                    icon: app.icon,
                    isActive: app.isActive,
                    pid: pid,
                    lastFocusTime: lastFocusTime
                )
            }
            .sorted { lhs, rhs in
                let excludedManager = ExcludedAppsManager.shared
                let lhsExcluded = excludedManager.isExcluded(lhs.bundleIdentifier)
                let rhsExcluded = excludedManager.isExcluded(rhs.bundleIdentifier)

                // Excluded apps first
                if lhsExcluded != rhsExcluded {
                    return lhsExcluded && !rhsExcluded
                }

                // Then active apps
                if lhs.isActive != rhs.isActive {
                    return lhs.isActive && !rhs.isActive
                }

                // Then alphabetical
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        self.apps = running
        // Prune selections that no longer exist
        selectedIDs = selectedIDs.intersection(running.map { $0.id })
    }

    func isSelected(_ app: RunningApp) -> Bool {
        selectedIDs.contains(app.id)
    }

    func toggle(_ app: RunningApp) {
        if selectedIDs.contains(app.id) {
            selectedIDs.remove(app.id)
        } else {
            selectedIDs.insert(app.id)
        }
    }

    func toggleSelectAll() {
        if areAllNonExcludedSelected() {
            // Deselect all
            selectedIDs.removeAll()
        } else {
            // Select all non-excluded apps
            let excludedManager = ExcludedAppsManager.shared
            selectedIDs = Set(
                apps.filter { !excludedManager.isExcluded($0.bundleIdentifier) }.map { $0.id })
        }
    }

    func areAllNonExcludedSelected() -> Bool {
        let excludedManager = ExcludedAppsManager.shared
        let nonExcludedApps = apps.filter { !excludedManager.isExcluded($0.bundleIdentifier) }

        guard !nonExcludedApps.isEmpty else { return false }

        let nonExcludedIDs = Set(nonExcludedApps.map { $0.id })
        return nonExcludedIDs.isSubset(of: selectedIDs)
            && nonExcludedIDs.count == nonExcludedIDs.intersection(selectedIDs).count
    }

    func isExcluded(_ app: RunningApp) -> Bool {
        return ExcludedAppsManager.shared.isExcluded(app.bundleIdentifier)
    }

    // Quit all selected apps using a "VacuumClone-like" approach:
    // - Activate target
    // - Send Quit Apple Event (kAEQuitApplication)
    // - Process sequentially with small delays
    // - Report remaining apps
    func quitSelectedApps() {
        // Resolve selected pids to NSRunningApplication instances.
        let selectedPIDs = Set(selectedIDs.map(pid_t.init))
        let targets = NSWorkspace.shared.runningApplications.filter {
            selectedPIDs.contains($0.processIdentifier)
        }

        guard !targets.isEmpty else {
            return
        }

        print("🎯 Attempting to quit \(targets.count) app(s)")

        Task { @MainActor in
            var successCount = 0

            for app in targets {
                let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
                print("📱 Processing: \(appName)")

                // 1) Activate so any save/confirmation sheets are visible.
                _ = app.activate(options: [.activateAllWindows])

                // Give focus time to transfer.
                try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2s

                // 2) Send Quit Apple Event (equivalent to user selecting Quit / Cmd-Q).
                let sent = sendQuitAppleEventDirect(to: app)

                // 3) Fallback if Apple Event failed immediately.
                if sent == false {
                    print("⚠️ Apple Event failed, trying terminate() for \(appName)")
                    let terminated = app.terminate()
                    if !terminated {
                        print("❌ terminate() also failed for \(appName)")
                    }
                } else {
                    successCount += 1
                }

                // Allow time for the app to react and possibly show dialogs.
                try? await Task.sleep(nanoseconds: 400_000_000)  // 0.4s
            }

            // After a small delay, check which ones are still running and report.
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s
            let stillRunningPIDs = Set(
                NSWorkspace.shared.runningApplications.map { $0.processIdentifier })
            let remaining = targets.filter { stillRunningPIDs.contains($0.processIdentifier) }

            if remaining.isEmpty {
                print("✅ All apps quit successfully")
            } else {
                let names = remaining.compactMap { $0.localizedName ?? $0.bundleIdentifier }.joined(
                    separator: ", ")
                print("⚠️ Still running: \(names)")
            }

            self.reload()
        }
    }

    // Focus/activate an app by bringing it to the front
    func focusApp(_ app: RunningApp) {
        // Find the NSRunningApplication instance for this app
        if let runningApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.processIdentifier == app.pid
        }) {
            // Activate the app, bringing it to the front
            runningApp.activate(options: [.activateAllWindows])
            print("🎯 Focused app: \(app.name)")
        }
    }

    // Send a Quit Apple Event (kAEQuitApplication) to the target app using low-level Apple Events.
    // Returns true if the event was sent (not necessarily that the app quit).
    private func sendQuitAppleEventDirect(to app: NSRunningApplication) -> Bool {
        guard let bundleID = app.bundleIdentifier else {
            print("⚠️ No bundle ID for app")
            return false
        }

        // Try using NSAppleScript to send quit command
        var error: NSDictionary?
        let script = NSAppleScript(source: "tell application id \"\(bundleID)\" to quit")
        let result = script?.executeAndReturnError(&error)

        if let error = error {
            print("❌ AppleScript error quitting \(bundleID): \(error)")
            return false
        }

        print("✅ Sent quit command to \(bundleID)")
        return result != nil
    }
}
