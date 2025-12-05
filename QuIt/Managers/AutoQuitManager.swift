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
    
    @Published var respectExcludeApps: Bool = true { // Respect exclude apps list
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
    
    @Published var defaultTimeout: TimeInterval = 300 { // 5 minutes default
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
    
    @Published var appTimeouts: [String: TimeInterval] = [:] { // bundleID -> custom timeout
        didSet {
            if !isLoading {
                saveSettings()
            }
        }
    }
    
    @Published var notifyOnAutoQuit: Bool = true { // Show notification when app is auto-quit
        didSet {
            if !isLoading {
                saveSettings()
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
        
        content.body = "\(appName) was automatically quit after \(timeoutString) of inactivity.\n\nQuit at: \(dateTimeString)"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "autoquit-\(bundleID)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Deliver immediately
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
            respectExcludeApps = true // Default behavior
        }
        
        // Load notifyOnAutoQuit, default to true if not set
        if UserDefaults.standard.object(forKey: notifyOnAutoQuitKey) != nil {
            notifyOnAutoQuit = UserDefaults.standard.bool(forKey: notifyOnAutoQuitKey)
        } else {
            notifyOnAutoQuit = true // Default behavior
        }
        
        let savedDefaultTimeout = UserDefaults.standard.double(forKey: defaultTimeoutKey)
        if savedDefaultTimeout > 0 {
            defaultTimeout = savedDefaultTimeout
        }
        
        if let data = UserDefaults.standard.data(forKey: appTimeoutsKey),
           let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data) {
            appTimeouts = decoded
        }
        
        isLoading = false
        
        print("✅ Auto-quit settings loaded from storage:")
        print("   - Enabled: \(isEnabled)")
        print("   - Respect exclude apps: \(respectExcludeApps)")
        print("   - Notify on auto-quit: \(notifyOnAutoQuit)")
        print("   - Default timeout: \(Int(defaultTimeout))s (\(Int(defaultTimeout/60))m)")
        print("   - Custom timeouts: \(appTimeouts.count) apps")
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(isEnabled, forKey: isEnabledKey)
        UserDefaults.standard.set(respectExcludeApps, forKey: respectExcludeAppsKey)
        UserDefaults.standard.set(notifyOnAutoQuit, forKey: notifyOnAutoQuitKey)
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
        print("   - Default timeout: \(Int(defaultTimeout))s")
        print("   - Custom timeouts: \(appTimeouts.count) apps")
    }
    
    func getTimeout(for bundleID: String?) -> TimeInterval {
        guard let bundleID = bundleID,
              let customTimeout = appTimeouts[bundleID] else {
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
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            
            // Don't process QuIt itself
            let currentPID = NSRunningApplication.current.processIdentifier
            guard app.processIdentifier != currentPID else {
                return
            }
            
            // Cancel timer for this app (it's now active)
            self.cancelTimer(for: bundleID)
            self.updateLastActivity()
            print("✅ App activated: \(bundleID) - timer cancelled")
        }
        
        // Listen for app deactivation (app becomes inactive)
        let deactivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            
            // Don't schedule timer for QuIt itself!
            let currentPID = NSRunningApplication.current.processIdentifier
            guard app.processIdentifier != currentPID else {
                print("⏭️ Skipping timer for QuIt itself")
                return
            }
            
            // Schedule timer for this app
            self.scheduleTimerForApp(bundleID, app: app)
            self.updateLastActivity()
            print("⏸️ App deactivated: \(bundleID) - timer scheduled")
        }
        
        // Listen for app termination (cleanup)
        let terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            
            // Don't process QuIt itself (shouldn't happen, but safety check)
            let currentPID = NSRunningApplication.current.processIdentifier
            guard app.processIdentifier != currentPID else {
                return
            }
            
            // Clean up timer for terminated app
            self.cancelTimer(for: bundleID)
            print("🗑️ App terminated: \(bundleID) - timer cleaned up")
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
        
        // First, ensure all running apps have a focus time recorded
        let allApps = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != currentPID && $0.activationPolicy == .regular
        }
        
        for app in allApps {
            guard let bundleID = app.bundleIdentifier else { continue }
            
            // If no focus time exists, record one now (conservative approach)
            if focusTracker.getLastFocusTime(for: bundleID) == nil {
                // Record current time as last focus for existing apps
                // This means they'll start their timeout from now
                focusTracker.recordInitialFocusTime(for: bundleID)
                print("   Initialized focus time for: \(app.localizedName ?? bundleID)")
            }
        }
        
        // Now schedule timers for inactive apps
        let inactiveApps = allApps.filter { app in
            guard !app.isActive,
                  let bundleID = app.bundleIdentifier else {
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
        guard isEnabled else {
            print("⚠️ Auto-quit disabled, not scheduling timer for \(bundleID)")
            return
        }
        
        // CRITICAL: Never schedule a timer for QuIt itself!
        let currentPID = NSRunningApplication.current.processIdentifier
        guard app.processIdentifier != currentPID else {
            print("🛡️ SAFETY: Prevented QuIt from scheduling itself for auto-quit")
            return
        }
        
        let focusTracker = AppFocusTracker.shared
        let excludedManager = ExcludedAppsManager.shared
        
        // Don't schedule for excluded apps (if respectExcludeApps is enabled)
        if respectExcludeApps && excludedManager.isExcluded(bundleID) {
            print("⚠️ \(bundleID) is excluded, not scheduling timer")
            return
        }
        
        // Get last focus time
        guard let lastFocusTime = focusTracker.getLastFocusTime(for: bundleID) else {
            print("⚠️ No focus time for \(bundleID), skipping timer")
            return
        }
        
        // Cancel existing timer if any
        cancelTimer(for: bundleID)
        
        // Calculate time until quit
        let timeout = getTimeout(for: bundleID)
        
        let appName = app.localizedName ?? bundleID
        
        // Check if timeout is 0 (never quit)
        if timeout == 0 {
            print("⏭️ \(appName) has timeout of 0, skipping (never quit)")
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
        let timer = Timer.scheduledTimer(withTimeInterval: timeUntilQuit, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            print("⏰ Timer fired for \(bundleID)")
            
            // Find app by PID (more reliable than weak reference)
            guard let runningApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.processIdentifier == appPID && $0.bundleIdentifier == bundleID
            }) else {
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
            
            // Quit the app
            print("🔥 Attempting to quit: \(appName)")
            self.quitApp(runningApp)
            self.cancelTimer(for: bundleID)
        }
        
        appTimers[bundleID] = timer
        updateTimersCount()
        
        print("⏰ Timer scheduled for \(appName): will quit in \(Int(timeUntilQuit))s (timeout: \(Int(timeout))s)")
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
        }
    }
    
    private func rescheduleAllTimers() {
        let currentTimers = Array(appTimers.keys)
        for bundleID in currentTimers {
            rescheduleTimerForApp(bundleID)
        }
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
    
    private func quitApp(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        let appName = app.localizedName ?? bundleID
        let timeout = getTimeout(for: bundleID)
        
        print("🔄 Auto-quit triggered for: \(appName)")
        
        var error: NSDictionary?
        let script = NSAppleScript(source: "tell application id \"\(bundleID)\" to quit")
        _ = script?.executeAndReturnError(&error)
        
        if let error = error {
            print("❌ Auto-quit failed for \(bundleID): \(error)")
        } else {
            print("✅ Auto-quit command sent to: \(appName)")
            // Send notification if enabled with timeout info
            sendNotification(for: appName, bundleID: bundleID, timeout: timeout)
        }
    }
}

