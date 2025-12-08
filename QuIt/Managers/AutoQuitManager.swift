//
//  AutoQuitManager.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import AppKit
import Combine
import Foundation
import UserNotifications

// Manager for auto-quit feature with event-driven individual timers
class AutoQuitManager: ObservableObject {
    static let shared = AutoQuitManager()

    @Published var isEnabled: Bool = false {
        didSet {
            if !isLoading {
                saveSettings()
                NotificationCenter.default.post(name: .autoQuitSettingsDidChange, object: nil)
            }
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }

    @Published var respectExcludeApps: Bool = true {  // Respect exclude apps list
        didSet {
            if !isLoading {
                saveSettings()
                NotificationCenter.default.post(name: .autoQuitSettingsDidChange, object: nil)
            }
            // Reschedule all timers with new exclusion rules
            if isEnabled {
                rescheduleAllTimers()
            }
        }
    }

    @Published var defaultTimeout: TimeInterval = 300 {  // 5 minutes default
        didSet {
            if !isLoading {
                saveSettings()
                NotificationCenter.default.post(name: .autoQuitSettingsDidChange, object: nil)
            }
            // Reschedule all timers with new default
            if isEnabled {
                rescheduleAllTimers()
            }
        }
    }

    @Published var appTimeouts: [String: TimeInterval] = [:] {  // bundleID -> custom timeout
        didSet {
            if !isLoading {
                saveSettings()
            }
        }
    }

    @Published var notifyOnAutoQuit: Bool = true {  // Show notification when app is auto-quit
        didSet {
            if !isLoading {
                saveSettings()
            }
        }
    }

    @Published var onlyCustomTimeouts: Bool = false {  // Only auto-quit apps with custom timeout settings
        didSet {
            if !isLoading {
                saveSettings()
                NotificationCenter.default.post(name: .autoQuitSettingsDidChange, object: nil)
            }
            // Reschedule all timers with new mode
            if isEnabled {
                rescheduleAllTimers()
            }
        }
    }

    @Published var activeTimersCount: Int = 0
    @Published var lastActivityTime: Date?

    private let isEnabledKey = "autoQuitEnabled"
    private let respectExcludeAppsKey = "autoQuitRespectExcludeApps"
    private let defaultTimeoutKey = "autoQuitDefaultTimeout"
    private let appTimeoutsKey = "autoQuitAppTimeouts"
    private let notifyOnAutoQuitKey = "autoQuitNotifyOnAutoQuit"
    private let onlyCustomTimeoutsKey = "autoQuitOnlyCustomTimeouts"

    // Track individual timers per app
    private var appTimers: [String: Timer] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isLoading = false

    private init() {
        loadSettings()
        requestNotificationPermissions()

        if isEnabled {
            startMonitoring()
        }

        print("✅ AutoQuitManager initialized successfully")
    }

    private func requestNotificationPermissions() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("✅ Notification permission granted")
            } else if let error = error {
                print("❌ Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    private func sendNotification(for appName: String, bundleID: String, timeout: TimeInterval) {
        guard notifyOnAutoQuit else { return }

        let content = UNMutableNotificationContent()
        content.title = "App Auto-Quit"

        // Format timeout duration
        let timeoutString: String
        if timeout >= 3600 {
            let hours = Int(timeout / 3600)
            let minutes = Int((timeout.truncatingRemainder(dividingBy: 3600)) / 60)
            if minutes > 0 {
                timeoutString = "\(hours)h \(minutes)m"
            } else {
                timeoutString = "\(hours)h"
            }
        } else if timeout >= 60 {
            let minutes = Int(timeout / 60)
            timeoutString = "\(minutes)m"
        } else {
            timeoutString = "\(Int(timeout))s"
        }

        // Format current date/time
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium
        let dateTimeString = dateFormatter.string(from: Date())

        content.body =
            "\(appName) was automatically quit after \(timeoutString) of inactivity.\n\nQuit at: \(dateTimeString)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "autoquit-\(bundleID)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil  // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send notification: \(error.localizedDescription)")
            } else {
                print("📬 Notification sent for: \(appName)")
            }
        }
    }

    deinit {
        stopMonitoring()
    }

    private func loadSettings() {
        isLoading = true

        isEnabled = UserDefaults.standard.bool(forKey: isEnabledKey)

        // Load respectExcludeApps, default to true if not set
        if UserDefaults.standard.object(forKey: respectExcludeAppsKey) != nil {
            respectExcludeApps = UserDefaults.standard.bool(forKey: respectExcludeAppsKey)
        } else {
            respectExcludeApps = true  // Default behavior
        }

        // Load notifyOnAutoQuit, default to true if not set
        if UserDefaults.standard.object(forKey: notifyOnAutoQuitKey) != nil {
            notifyOnAutoQuit = UserDefaults.standard.bool(forKey: notifyOnAutoQuitKey)
        } else {
            notifyOnAutoQuit = true  // Default behavior
        }

        // Load onlyCustomTimeouts, default to false if not set
        if UserDefaults.standard.object(forKey: onlyCustomTimeoutsKey) != nil {
            onlyCustomTimeouts = UserDefaults.standard.bool(forKey: onlyCustomTimeoutsKey)
        } else {
            onlyCustomTimeouts = false  // Default behavior: auto-quit all apps
        }

        let savedDefaultTimeout = UserDefaults.standard.double(forKey: defaultTimeoutKey)
        if savedDefaultTimeout > 0 {
            defaultTimeout = savedDefaultTimeout
        }

        if let data = UserDefaults.standard.data(forKey: appTimeoutsKey),
            let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data)
        {
            appTimeouts = decoded
        }

        isLoading = false

        print("✅ Auto-quit settings loaded from storage:")
        print("   - Enabled: \(isEnabled)")
        print("   - Respect exclude apps: \(respectExcludeApps)")
        print("   - Notify on auto-quit: \(notifyOnAutoQuit)")
        print("   - Only custom timeouts: \(onlyCustomTimeouts)")
        print("   - Default timeout: \(Int(defaultTimeout))s (\(Int(defaultTimeout/60))m)")
        print("   - Custom timeouts: \(appTimeouts.count) apps")
    }

    private func saveSettings() {
        UserDefaults.standard.set(isEnabled, forKey: isEnabledKey)
        UserDefaults.standard.set(respectExcludeApps, forKey: respectExcludeAppsKey)
        UserDefaults.standard.set(notifyOnAutoQuit, forKey: notifyOnAutoQuitKey)
        UserDefaults.standard.set(onlyCustomTimeouts, forKey: onlyCustomTimeoutsKey)
        UserDefaults.standard.set(defaultTimeout, forKey: defaultTimeoutKey)

        if let encoded = try? JSONEncoder().encode(appTimeouts) {
            UserDefaults.standard.set(encoded, forKey: appTimeoutsKey)
        } else {
            print("⚠️ Failed to encode appTimeouts")
        }

        // Force immediate save to disk for all settings
        UserDefaults.standard.synchronize()

        print("💾 Auto-quit settings saved to storage:")
        print("   - Enabled: \(isEnabled)")
        print("   - Respect exclude apps: \(respectExcludeApps)")
        print("   - Notify on auto-quit: \(notifyOnAutoQuit)")
        print("   - Only custom timeouts: \(onlyCustomTimeouts)")
        print("   - Default timeout: \(Int(defaultTimeout))s")
        print("   - Custom timeouts: \(appTimeouts.count) apps")
    }

    func getTimeout(for bundleID: String?) -> TimeInterval {
        guard let bundleID = bundleID,
            let customTimeout = appTimeouts[bundleID]
        else {
            return defaultTimeout
        }
        return customTimeout
    }

    func setTimeout(for bundleID: String, timeout: TimeInterval) {
        print("⚙️ Setting custom timeout for \(bundleID): \(Int(timeout))s")
        appTimeouts[bundleID] = timeout
        objectWillChange.send()
        NotificationCenter.default.post(name: .autoQuitSettingsDidChange, object: nil)

        // If app is currently running and inactive, reschedule its timer
        if isEnabled {
            rescheduleTimerForApp(bundleID)
        }
    }

    func removeTimeout(for bundleID: String) {
        print("🗑️ Removing custom timeout for \(bundleID)")
        appTimeouts.removeValue(forKey: bundleID)
        objectWillChange.send()
        NotificationCenter.default.post(name: .autoQuitSettingsDidChange, object: nil)

        // Reschedule with default timeout
        if isEnabled {
            rescheduleTimerForApp(bundleID)
        }
    }

    func hasCustomTimeout(for bundleID: String?) -> Bool {
        guard let bundleID = bundleID else { return false }
        return appTimeouts.keys.contains(bundleID)
    }

    func getActiveTimerBundleIDs() -> [String] {
        return Array(appTimers.keys)
    }

    // MARK: - Event-Driven Monitoring

    private func startMonitoring() {
        stopMonitoring()

        print("🚀 Auto-quit started with event-driven approach")

        // Listen for app activation (app becomes active)
        let activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                let bundleID = app.bundleIdentifier
            else { return }

            // Don't process QuIt itself
            let currentPID = NSRunningApplication.current.processIdentifier
            guard app.processIdentifier != currentPID else {
                return
            }

            // Cancel timer for this app (it's now active)
            self.cancelTimer(for: bundleID)
            self.updateLastActivity()

            DebugLogger.shared.log(
                "App activated: \(app.localizedName ?? bundleID) [\(bundleID)] - timer cancelled",
                level: .debug)
        }

        // Listen for app deactivation (app becomes inactive)
        let deactivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                let bundleID = app.bundleIdentifier
            else { return }

            // Don't schedule timer for QuIt itself!
            let currentPID = NSRunningApplication.current.processIdentifier
            guard app.processIdentifier != currentPID else {
                print("⏭️ Skipping timer for QuIt itself")
                return
            }

            // Delay slightly to let windows fully close before checking
            // This prevents scheduling timers for menu bar apps whose windows are still closing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }

                // Re-check if app still exists and is still inactive
                guard
                    let currentApp = NSWorkspace.shared.runningApplications.first(where: {
                        $0.bundleIdentifier == bundleID
                    }), !currentApp.isActive
                else {
                    print("⏭️ Skipping timer for \(bundleID) - app activated or quit")
                    return
                }

                // Schedule timer for this app
                self.scheduleTimerForApp(bundleID, app: currentApp)
                self.updateLastActivity()

                DebugLogger.shared.log(
                    "App deactivated: \(currentApp.localizedName ?? bundleID) [\(bundleID)] - timer check initiated",
                    level: .debug)
            }
        }

        // Listen for app termination (cleanup)
        let terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                let bundleID = app.bundleIdentifier
            else { return }

            // Don't process QuIt itself (shouldn't happen, but safety check)
            let currentPID = NSRunningApplication.current.processIdentifier
            guard app.processIdentifier != currentPID else {
                return
            }

            // Clean up timer for terminated app
            self.cancelTimer(for: bundleID)

            DebugLogger.shared.log(
                "App terminated: \(app.localizedName ?? bundleID) [\(bundleID)] - timer cleaned up",
                level: .debug)
        }

        workspaceObservers = [activationObserver, deactivationObserver, terminationObserver]

        // Schedule timers for all currently inactive apps
        scheduleTimersForCurrentlyInactiveApps()
    }

    private func stopMonitoring() {
        // Remove all observers
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        // Cancel all timers
        for (bundleID, timer) in appTimers {
            timer.invalidate()
            print("⏹️ Timer cancelled for: \(bundleID)")
        }
        appTimers.removeAll()
        updateTimersCount()

        print("⏹️ Auto-quit monitoring stopped")
    }

    private func scheduleTimersForCurrentlyInactiveApps() {
        let focusTracker = AppFocusTracker.shared
        let excludedManager = ExcludedAppsManager.shared
        let currentPID = NSRunningApplication.current.processIdentifier

        print("📋 Initializing timers for currently running apps...")

        // First, reset all focus times to current time to avoid using stale cache
        // This ensures timeout countdown starts fresh from when QuIt launches
        let allApps = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != currentPID && $0.activationPolicy == .regular
        }

        for app in allApps {
            guard let bundleID = app.bundleIdentifier else { continue }

            // Always reset focus time to current time on startup
            // This prevents using cached times from previous sessions
            focusTracker.resetFocusTime(for: bundleID)
            print("   Reset focus time for: \(app.localizedName ?? bundleID)")
        }

        // Now schedule timers for inactive apps
        let inactiveApps = allApps.filter { app in
            guard !app.isActive,
                let bundleID = app.bundleIdentifier
            else {
                return false
            }

            // Check exclusions only if respectExcludeApps is enabled
            if respectExcludeApps && excludedManager.isExcluded(bundleID) {
                return false
            }

            return true
        }

        print("📋 Scheduling timers for \(inactiveApps.count) inactive apps")
        for app in inactiveApps {
            if let bundleID = app.bundleIdentifier {
                scheduleTimerForApp(bundleID, app: app)
            }
        }
    }

    private func scheduleTimerForApp(_ bundleID: String, app: NSRunningApplication) {
        // IMPORTANT: Always cancel existing timer first before any checks
        // This ensures timers are properly cleaned up when settings change
        cancelTimer(for: bundleID)

        guard isEnabled else {
            DebugLogger.shared.log(
                "Auto-quit disabled, not scheduling timer for \(bundleID)", level: .debug)
            return
        }

        // CRITICAL: Never schedule a timer for QuIt itself!
        let currentPID = NSRunningApplication.current.processIdentifier
        guard app.processIdentifier != currentPID else {
            DebugLogger.shared.log(
                "SAFETY: Prevented QuIt from scheduling itself for auto-quit", level: .warning)
            return
        }

        let focusTracker = AppFocusTracker.shared
        let excludedManager = ExcludedAppsManager.shared

        // Don't schedule for excluded apps (if respectExcludeApps is enabled)
        if respectExcludeApps && excludedManager.isExcluded(bundleID) {
            DebugLogger.shared.log("\(bundleID) is excluded, not scheduling timer", level: .debug)
            return
        }

        // If onlyCustomTimeouts mode is enabled, only auto-quit apps with custom timeout settings
        if onlyCustomTimeouts && !hasCustomTimeout(for: bundleID) {
            DebugLogger.shared.log(
                "\(bundleID) has no custom timeout (onlyCustomTimeouts mode), skipping",
                level: .debug)
            return
        }

        // Get last focus time
        guard let lastFocusTime = focusTracker.getLastFocusTime(for: bundleID) else {
            DebugLogger.shared.log("No focus time for \(bundleID), skipping timer", level: .debug)
            return
        }

        // Calculate time until quit
        let timeout = getTimeout(for: bundleID)

        let appName = app.localizedName ?? bundleID

        // Check if timeout is 0 (never quit)
        if timeout == 0 {
            DebugLogger.shared.log(
                "\(appName) has timeout of 0, skipping (never quit)", level: .debug)
            return
        }

        // IMPORTANT: Don't schedule timer for menu bar apps with no visible windows
        // Apps like CleanShot X open windows temporarily but should stay running as menu bar apps
        if hasNoVisibleWindows(app) {
            DebugLogger.shared.log(
                "\(appName) has no visible windows (menu bar app), skipping timer", level: .debug)
            return
        }

        // Also check activation policy - accessory apps are typically menu bar apps
        if app.activationPolicy == .accessory {
            DebugLogger.shared.log(
                "\(appName) is an accessory app (menu bar app), skipping timer", level: .debug)
            return
        }

        let timeSinceLastFocus = Date().timeIntervalSince(lastFocusTime)
        let timeUntilQuit = max(0, timeout - timeSinceLastFocus)

        // If already past timeout, quit immediately
        if timeUntilQuit == 0 {
            print("🚨 \(appName) already past timeout, quitting immediately")
            quitApp(app)
            return
        }

        // Store app pid for later lookup (weak reference might fail)
        let appPID = app.processIdentifier

        // Schedule new timer
        let timer = Timer.scheduledTimer(withTimeInterval: timeUntilQuit, repeats: false) {
            [weak self] _ in
            guard let self = self else { return }

            print("⏰ Timer fired for \(bundleID)")

            // Find app by PID (more reliable than weak reference)
            guard
                let runningApp = NSWorkspace.shared.runningApplications.first(where: {
                    $0.processIdentifier == appPID && $0.bundleIdentifier == bundleID
                })
            else {
                print("⚠️ App \(bundleID) not found, might have already quit")
                self.cancelTimer(for: bundleID)
                return
            }

            // Double-check app is still inactive and not excluded
            guard !runningApp.isActive else {
                print("⚠️ Skipping quit for \(bundleID) - became active")
                self.cancelTimer(for: bundleID)
                return
            }

            // Check exclusions only if respectExcludeApps is enabled
            if self.respectExcludeApps && excludedManager.isExcluded(bundleID) {
                print("⚠️ Skipping quit for \(bundleID) - now excluded")
                self.cancelTimer(for: bundleID)
                return
            }

            // Check if app now has no visible windows (became a menu bar only app)
            if self.hasNoVisibleWindows(runningApp) {
                print("⚠️ Skipping quit for \(bundleID) - no visible windows (menu bar app)")
                self.cancelTimer(for: bundleID)
                return
            }

            // Check if app is an accessory (menu bar) app
            if runningApp.activationPolicy == .accessory {
                print("⚠️ Skipping quit for \(bundleID) - accessory/menu bar app")
                self.cancelTimer(for: bundleID)
                return
            }

            // Quit the app
            print("🔥 Attempting to quit: \(appName)")
            self.quitApp(runningApp)
            self.cancelTimer(for: bundleID)
        }

        appTimers[bundleID] = timer
        updateTimersCount()

        DebugLogger.shared.log(
            "Timer scheduled for \(appName) [\(bundleID)]: will quit in \(Int(timeUntilQuit))s (timeout: \(Int(timeout))s)",
            level: .info)
    }

    private func cancelTimer(for bundleID: String) {
        if let timer = appTimers[bundleID] {
            timer.invalidate()
            appTimers.removeValue(forKey: bundleID)
            updateTimersCount()
        }
    }

    private func rescheduleTimerForApp(_ bundleID: String) {
        // Find the app and reschedule
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleID && !$0.isActive
        }) {
            scheduleTimerForApp(bundleID, app: app)
        } else {
            // App is no longer running or is now active, cancel its timer
            cancelTimer(for: bundleID)
        }
    }

    private func rescheduleAllTimers() {
        print("🔄 Reschedulating all timers based on updated settings...")

        // Get all apps that currently have timers
        let currentTimers = Array(appTimers.keys)

        // Get all currently running inactive apps
        let currentPID = NSRunningApplication.current.processIdentifier
        let inactiveApps = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != currentPID && $0.activationPolicy == .regular && !$0.isActive
                && $0.bundleIdentifier != nil
        }

        // Combine both lists to ensure we check all relevant apps
        var allBundleIDs = Set(currentTimers)
        for app in inactiveApps {
            if let bundleID = app.bundleIdentifier {
                allBundleIDs.insert(bundleID)
            }
        }

        // Reschedule or cancel each app's timer based on current settings
        for bundleID in allBundleIDs {
            if let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == bundleID && !$0.isActive
            }) {
                scheduleTimerForApp(bundleID, app: app)
            } else {
                // App is no longer running or is now active, cancel its timer
                cancelTimer(for: bundleID)
            }
        }

        print("✅ Rescheduled all timers. Active timers: \(appTimers.count)")
    }

    private func updateTimersCount() {
        DispatchQueue.main.async {
            self.activeTimersCount = self.appTimers.count
        }
    }

    private func updateLastActivity() {
        DispatchQueue.main.async {
            self.lastActivityTime = Date()
        }
    }

    private func hasNoVisibleWindows(_ app: NSRunningApplication) -> Bool {
        // Use CGWindowListCopyWindowInfo to check if app has any visible windows
        // Use .optionAll to detect windows across all spaces, not just the current one
        guard
            let windows = CGWindowListCopyWindowInfo(
                [.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else {
            return true
        }

        let appPID = app.processIdentifier
        var windowCount = 0

        // Check if this app has any on-screen windows
        for window in windows {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                ownerPID == appPID
            else {
                continue
            }

            // Get window properties
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            let alpha = window[kCGWindowAlpha as String] as? CGFloat ?? 0
            let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            let width = bounds["Width"] ?? 0
            let height = bounds["Height"] ?? 0

            // Filter out:
            // - Non-normal layers (menu bar items are at layer 25+)
            // - Invisible windows (alpha == 0)
            // - Tiny windows (likely status bar items or popups)
            if layer == 0 && alpha > 0 && width > 100 && height > 100 {
                windowCount += 1
            }
        }

        // If no substantial windows found, it's likely a menu bar only app
        let hasWindows = windowCount > 0

        if !hasWindows {
            print(
                "   📊 Window check for \(app.localizedName ?? "app"): 0 visible windows (menu bar app)"
            )
        } else {
            print(
                "   📊 Window check for \(app.localizedName ?? "app"): \(windowCount) visible window(s)"
            )
        }

        return !hasWindows
    }

    private func quitApp(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        let appName = app.localizedName ?? bundleID
        let timeout = getTimeout(for: bundleID)

        print("🔄 Auto-quit triggered for: \(appName)")

        var error: NSDictionary?
        let script = NSAppleScript(source: "tell application id \"\(bundleID)\" to quit")
        _ = script?.executeAndReturnError(&error)

        if let error = error {
            DebugLogger.shared.log(
                "Auto-quit failed for \(appName) [\(bundleID)]: \(error)", level: .error)
        } else {
            DebugLogger.shared.log(
                "Auto-quit command sent to: \(appName) [\(bundleID)] after \(Int(timeout))s timeout",
                level: .info)
            // Send notification if enabled with timeout info
            sendNotification(for: appName, bundleID: bundleID, timeout: timeout)
        }
    }
}
