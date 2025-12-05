//
//  ContentView.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

// Model to represent a running app snapshot
struct RunningApp: Identifiable, Hashable {
    // Use pid for uniqueness to avoid duplicate IDs in LazyVStack.
    let id: Int
    let bundleIdentifier: String?
    let name: String
    let icon: NSImage?
    let isActive: Bool
    let pid: pid_t
    let lastFocusTime: Date?
}

// Notification name for excluded apps changes and popover events
extension Notification.Name {
    static let excludedAppsDidChange = Notification.Name("excludedAppsDidChange")
    static let popoverWillOpen = Notification.Name("popoverWillOpen")
    static let autoQuitSettingsDidChange = Notification.Name("autoQuitSettingsDidChange")
}

// Manager to track app focus times for auto-quit feature
class AppFocusTracker: ObservableObject {
    static let shared = AppFocusTracker()
    
    private let focusTimesKey = "appFocusTimes"
    private var focusTimes: [String: Date] = [:]
    private var workspaceObserver: NSObjectProtocol?
    
    private init() {
        loadFocusTimes()
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    private func loadFocusTimes() {
        if let data = UserDefaults.standard.data(forKey: focusTimesKey),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            focusTimes = decoded
        }
    }
    
    private func saveFocusTimes() {
        if let encoded = try? JSONEncoder().encode(focusTimes) {
            UserDefaults.standard.set(encoded, forKey: focusTimesKey)
        }
    }
    
    private func startMonitoring() {
        // Monitor app activation events
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            
            // Record focus time
            self.recordFocusTime(for: bundleID)
        }
        
        // Record current active app on start
        if let activeApp = NSWorkspace.shared.frontmostApplication,
           let bundleID = activeApp.bundleIdentifier {
            recordFocusTime(for: bundleID)
        }
    }
    
    private func stopMonitoring() {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
    }
    
    private func recordFocusTime(for bundleID: String) {
        let now = Date()
        focusTimes[bundleID] = now
        saveFocusTimes()
        
        print("📍 App focus recorded: \(bundleID) at \(now)")
    }
    
    // Public method for AutoQuitManager to initialize focus times
    func recordInitialFocusTime(for bundleID: String) {
        // Only record if not already tracked
        if focusTimes[bundleID] == nil {
            focusTimes[bundleID] = Date()
            saveFocusTimes()
        }
    }
    
    func getLastFocusTime(for bundleID: String?) -> Date? {
        guard let bundleID = bundleID else { return nil }
        return focusTimes[bundleID]
    }
    
    func getAllFocusTimes() -> [String: Date] {
        return focusTimes
    }
    
    func clearFocusTime(for bundleID: String) {
        focusTimes.removeValue(forKey: bundleID)
        saveFocusTimes()
    }
    
    func clearAllFocusTimes() {
        focusTimes.removeAll()
        saveFocusTimes()
    }
    
    func getTimeSinceLastFocus(for bundleID: String?) -> TimeInterval? {
        guard let lastFocus = getLastFocusTime(for: bundleID) else { return nil }
        return Date().timeIntervalSince(lastFocus)
    }
}

// Manager for auto-quit feature with event-driven individual timers
class AutoQuitManager: ObservableObject {
    static let shared = AutoQuitManager()
    
    @Published var isEnabled: Bool = false {
        didSet {
            saveSettings()
            NotificationCenter.default.post(name: .autoQuitSettingsDidChange, object: nil)
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }
    
    @Published var respectExcludeApps: Bool = true { // Respect exclude apps list
        didSet {
            saveSettings()
            NotificationCenter.default.post(name: .autoQuitSettingsDidChange, object: nil)
            // Reschedule all timers with new exclusion rules
            if isEnabled {
                rescheduleAllTimers()
            }
        }
    }
    
    @Published var defaultTimeout: TimeInterval = 300 { // 5 minutes default
        didSet {
            saveSettings()
            NotificationCenter.default.post(name: .autoQuitSettingsDidChange, object: nil)
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
    
    @Published var activeTimersCount: Int = 0
    @Published var lastActivityTime: Date?
    
    private let isEnabledKey = "autoQuitEnabled"
    private let respectExcludeAppsKey = "autoQuitRespectExcludeApps"
    private let defaultTimeoutKey = "autoQuitDefaultTimeout"
    private let appTimeoutsKey = "autoQuitAppTimeouts"
    
    // Track individual timers per app
    private var appTimers: [String: Timer] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isLoading = false
    
    private init() {
        loadSettings()
        
        if isEnabled {
            startMonitoring()
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
        print("   - Default timeout: \(Int(defaultTimeout))s (\(Int(defaultTimeout/60))m)")
        print("   - Custom timeouts: \(appTimeouts.count) apps")
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(isEnabled, forKey: isEnabledKey)
        UserDefaults.standard.set(respectExcludeApps, forKey: respectExcludeAppsKey)
        UserDefaults.standard.set(defaultTimeout, forKey: defaultTimeoutKey)
        
        if let encoded = try? JSONEncoder().encode(appTimeouts) {
            UserDefaults.standard.set(encoded, forKey: appTimeoutsKey)
            UserDefaults.standard.synchronize() // Force immediate save to disk
        }
        
        print("💾 Auto-quit settings saved to storage")
    }
    
    func getTimeout(for bundleID: String?) -> TimeInterval {
        guard let bundleID = bundleID,
              let customTimeout = appTimeouts[bundleID] else {
            return defaultTimeout
        }
        return customTimeout
    }
    
    func setTimeout(for bundleID: String, timeout: TimeInterval) {
        appTimeouts[bundleID] = timeout
        objectWillChange.send()
        NotificationCenter.default.post(name: .autoQuitSettingsDidChange, object: nil)
        
        // If app is currently running and inactive, reschedule its timer
        if isEnabled {
            rescheduleTimerForApp(bundleID)
        }
    }
    
    func removeTimeout(for bundleID: String) {
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
        
        print("🔄 Auto-quit triggered for: \(appName)")
        
        var error: NSDictionary?
        let script = NSAppleScript(source: "tell application id \"\(bundleID)\" to quit")
        _ = script?.executeAndReturnError(&error)
        
        if let error = error {
            print("❌ Auto-quit failed for \(bundleID): \(error)")
        } else {
            print("✅ Auto-quit command sent to: \(appName)")
        }
    }
}

// Model for an exclusion profile
struct ExclusionProfile: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var excludedBundleIDs: Set<String>

    init(id: UUID = UUID(), name: String, excludedBundleIDs: Set<String> = []) {
        self.id = id
        self.name = name
        self.excludedBundleIDs = excludedBundleIDs
    }
}

// Manager for excluded apps with persistence and profile support
class ExcludedAppsManager: ObservableObject {
    static let shared = ExcludedAppsManager()

    @Published var profiles: [ExclusionProfile] = []
    @Published var selectedProfileID: UUID? {
        didSet {
            saveSelectedProfile()
            NotificationCenter.default.post(name: .excludedAppsDidChange, object: nil)
        }
    }

    var currentProfile: ExclusionProfile? {
        if let selectedID = selectedProfileID {
            return profiles.first(where: { $0.id == selectedID })
        }
        return profiles.first
    }

    var excludedBundleIDs: Set<String> {
        currentProfile?.excludedBundleIDs ?? []
    }

    private let profilesKey = "excludedAppsProfiles"
    private let selectedProfileKey = "selectedExcludedAppsProfile"

    private init() {
        loadProfiles()

        // If no profiles exist, create a default one
        if profiles.isEmpty {
            let defaultProfile = ExclusionProfile(name: "Default", excludedBundleIDs: [])
            profiles = [defaultProfile]
            selectedProfileID = defaultProfile.id
            saveProfiles()
        } else {
            loadSelectedProfile()
        }
    }

    private func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: profilesKey),
            let decoded = try? JSONDecoder().decode([ExclusionProfile].self, from: data)
        {
            profiles = decoded
        }
    }

    private func saveProfiles() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(encoded, forKey: profilesKey)
        }
    }

    private func loadSelectedProfile() {
        if let uuidString = UserDefaults.standard.string(forKey: selectedProfileKey),
            let uuid = UUID(uuidString: uuidString),
            profiles.contains(where: { $0.id == uuid })
        {
            selectedProfileID = uuid
        } else {
            selectedProfileID = profiles.first?.id
        }
    }

    private func saveSelectedProfile() {
        if let selectedID = selectedProfileID {
            UserDefaults.standard.set(selectedID.uuidString, forKey: selectedProfileKey)
        }
    }

    func addExclusion(_ bundleID: String) {
        guard var profile = currentProfile,
            let index = profiles.firstIndex(where: { $0.id == profile.id })
        else { return }

        profile.excludedBundleIDs.insert(bundleID)
        profiles[index] = profile
        saveProfiles()
        objectWillChange.send()
        NotificationCenter.default.post(name: .excludedAppsDidChange, object: nil)
    }

    func removeExclusion(_ bundleID: String) {
        guard var profile = currentProfile,
            let index = profiles.firstIndex(where: { $0.id == profile.id })
        else { return }

        profile.excludedBundleIDs.remove(bundleID)
        profiles[index] = profile
        saveProfiles()
        objectWillChange.send()
        NotificationCenter.default.post(name: .excludedAppsDidChange, object: nil)
    }

    func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID = bundleID else { return false }
        return excludedBundleIDs.contains(bundleID)
    }

    func createProfile(name: String) {
        let newProfile = ExclusionProfile(name: name, excludedBundleIDs: [])
        profiles.append(newProfile)
        selectedProfileID = newProfile.id
        saveProfiles()
    }

    func deleteProfile(_ profile: ExclusionProfile) {
        guard profiles.count > 1 else { return }  // Keep at least one profile

        profiles.removeAll { $0.id == profile.id }

        if selectedProfileID == profile.id {
            selectedProfileID = profiles.first?.id
        }

        saveProfiles()
    }

    func renameProfile(_ profile: ExclusionProfile, to newName: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index].name = newName
        saveProfiles()
        objectWillChange.send()
    }

    func duplicateProfile(_ profile: ExclusionProfile) {
        let duplicate = ExclusionProfile(
            name: "\(profile.name) Copy",
            excludedBundleIDs: profile.excludedBundleIDs
        )
        profiles.append(duplicate)
        saveProfiles()
    }
}

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
        // Optional: skip apps that haven’t finished launching to avoid transient entries
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
                // Active app first, then alphabetical
                if lhs.isActive != rhs.isActive {
                    return lhs.isActive && !rhs.isActive
                }
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

struct ContentView: View {
    @StateObject private var model = RunningAppsModel()
    @ObservedObject private var excludedManager = ExcludedAppsManager.shared
    @ObservedObject private var autoQuitManager = AutoQuitManager.shared

    var body: some View {
        VStack(spacing: 12) {
            // First section: Running applications with checkboxes
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    Text("Running Apps")
                        .font(.headline)
                        .opacity(0.9)
                    Spacer(minLength: 0)
                    
                    HStack(spacing: 2) {
                        Menu {
                            ForEach(excludedManager.profiles) { profile in
                                Button {
                                    excludedManager.selectedProfileID = profile.id
                                    model.reload()
                                } label: {
                                    HStack {
                                        Text(profile.name)
                                        if excludedManager.selectedProfileID == profile.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(excludedManager.currentProfile?.name ?? "Default")
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                
                                if let count = excludedManager.currentProfile?.excludedBundleIDs.count, count > 0 {
                                    Text("(\(count))")
                                        .font(.caption2)
                                        .foregroundStyle(.yellow)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .frame(minWidth: 80, maxWidth: 120)

                        Button {
                            model.reload()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .imageScale(.medium)
                        }
                        .buttonStyle(.plain)
                        .help("Refresh")
                    }
                }
                
                // Status info (excluded apps and auto-quit)
                HStack(spacing: 12) {
                    // Excluded apps info
                    if let excludedCount = excludedManager.currentProfile?.excludedBundleIDs.count, excludedCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "eye.slash")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                            Text("\(excludedCount) app\(excludedCount == 1 ? "" : "s") excluded")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Auto-quit status
                    if autoQuitManager.isEnabled {
                        HStack(spacing: 6) {
                            Image(systemName: "timer")
                                .foregroundColor(.green)
                                .font(.caption)
                            
                            Text("Auto-Quit:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Text("\(Int(autoQuitManager.defaultTimeout / 60))m")
                                .font(.caption)
                                .foregroundStyle(.primary)
                            
                            if autoQuitManager.appTimeouts.count > 0 {
                                Text("(\(autoQuitManager.appTimeouts.count) custom)")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }
                }

                // Select/Deselect All checkbox
                HStack(spacing: 6) {
                    Toggle("", isOn: Binding(
                        get: { model.areAllNonExcludedSelected() },
                        set: { _ in model.toggleSelectAll() }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    
                    Text("Select All")
                        .font(.caption)
                }

                if model.apps.isEmpty {
                    Text("No running applications found.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(model.apps) { app in
                                let isExcluded = model.isExcluded(app)
                                HStack(spacing: 8) {
                                    // Checkbox (Toggle style)
                                    Toggle(
                                        "",
                                        isOn: Binding(
                                            get: { model.isSelected(app) },
                                            set: { _ in model.toggle(app) }
                                        )
                                    )
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()
                                    
                                    // App icon
                                    Image(nsImage: app.icon ?? NSImage())
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 20, height: 20)
                                        .cornerRadius(4)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                        )
                                        .opacity(isExcluded ? 0.6 : 1.0)

                                    // App name with time info
                                    HStack(spacing: 4) {
                                        Text(app.name)
                                            .font(.body)
                                            .lineLimit(1)
                                            .foregroundColor(isExcluded ? .yellow : .primary)

                                        if let lastFocusTime = app.lastFocusTime {
                                            Text(timeAgoString(from: lastFocusTime))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer(minLength: 8)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(
                                    app.isActive
                                        ? Color.white.opacity(0.08)
                                        : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(height: min(280, CGFloat(model.apps.count) * 32 + 12))
                }
            }

            Divider().opacity(0.6)

            // Footer actions
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Button {
                        // Quit all selected apps gracefully (normal quit).
                        model.quitSelectedApps()
                    } label: {
                        Label("Quit Apps", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.selectedIDs.isEmpty)

                    Spacer(minLength: 8)

                    Button {
                        openSettingsWindow()
                    } label: {
                        Image(systemName: "gear")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Settings")

                    Button(role: .destructive) {
                        NSApp.terminate(nil)
                    } label: {
                        Image(systemName: "power")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Quit QuIt")
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        )
        .frame(width: 320)
        .onAppear {
            // Load apps only when popover opens
            model.reload()
            // Auto-select all non-excluded apps after a brief delay
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s
                autoSelectAll()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .popoverWillOpen)) { _ in
            // Reload apps list every time popover opens
            model.reload()
            // Auto-select all non-excluded apps after a brief delay
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s
                autoSelectAll()
            }
        }
    }

    private func autoSelectAll() {
        // Select all non-excluded apps
        let excludedManager = ExcludedAppsManager.shared
        model.selectedIDs = Set(model.apps.filter { !excludedManager.isExcluded($0.bundleIdentifier) }.map { $0.id })
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
    
    private func openSettingsWindow() {
        // If window already exists, just bring it to front
        if let existingWindow = WindowManager.shared.settingsWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            existingWindow.center()
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        // Keep window in memory after closing to avoid memory issues
        window.isReleasedWhenClosed = false

        // Center on main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowSize = NSSize(width: 800, height: 700)
            let origin = NSPoint(
                x: screenFrame.midX - windowSize.width / 2,
                y: screenFrame.midY - windowSize.height / 2
            )
            window.setFrame(NSRect(origin: origin, size: windowSize), display: true)
        } else {
            window.center()
        }

        window.makeKeyAndOrderFront(nil)

        // Keep a reference to prevent deallocation
        WindowManager.shared.settingsWindow = window
    }
}

// Singleton to manage windows
class WindowManager {
    static let shared = WindowManager()
    var settingsWindow: NSWindow?

    private init() {}
}

struct SettingsView: View {
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Tab View
            TabView(selection: $selectedTab) {
                GeneralSettingsTabView()
                    .tabItem {
                        Label("General", systemImage: "gearshape")
                    }
                    .tag(0)

                AboutTabView()
                    .tabItem {
                        Label("About", systemImage: "info.circle")
                    }
                    .tag(1)

                ExcludeAppsTabView()
                    .tabItem {
                        Label("Exclude Apps", systemImage: "eye.slash")
                    }
                    .tag(2)
                
                AutoQuitTabView()
                    .tabItem {
                        Label("Auto-Quit", systemImage: "timer")
                    }
                    .tag(3)
                
                FocusTrackingTabView()
                    .tabItem {
                        Label("Focus Tracking", systemImage: "clock")
                    }
                    .tag(4)
            }
        }
        .frame(width: 800, height: 700)
    }
}

struct GeneralSettingsTabView: View {
    @State private var launchAtLogin: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General Settings")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Startup")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .onChange(of: launchAtLogin) { oldValue, newValue in
                        setLaunchAtLogin(enabled: newValue)
                    }

                Text("Automatically start QuIt when you log in to your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
        .onAppear {
            launchAtLogin = isLaunchAtLoginEnabled()
        }
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    private func setLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print(
                    "Failed to \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)"
                )
            }
        }
    }
}

struct AboutTabView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About QuIt")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Version 1.0")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("QuIt helps you quickly quit multiple applications at once.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Permissions")
                    .font(.headline)

                Text(
                    "QuIt requires Automation permission to quit other apps. If apps won't quit, check System Settings → Privacy & Security → Automation."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(20)
    }
}

struct ExcludeAppsTabView: View {
    @ObservedObject private var excludedManager = ExcludedAppsManager.shared
    @State private var showingNewProfileSheet = false
    @State private var newProfileName = ""
    @State private var showingRenameSheet = false
    @State private var profileToRename: ExclusionProfile?
    @State private var renameProfileName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Excluded Applications")
                .font(.headline)

            Text("Applications in this list will not appear in the running apps list.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            // Profile selector and management
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Profile:")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Picker(
                        "",
                        selection: Binding(
                            get: {
                                excludedManager.selectedProfileID ?? excludedManager.profiles.first?
                                    .id ?? UUID()
                            },
                            set: { excludedManager.selectedProfileID = $0 }
                        )
                    ) {
                        ForEach(excludedManager.profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    .frame(maxWidth: 200)

                    Spacer()

                    // Profile management buttons
                    Menu {
                        Button {
                            showingNewProfileSheet = true
                        } label: {
                            Label("New Profile", systemImage: "plus")
                        }

                        if let currentProfile = excludedManager.currentProfile {
                            Button {
                                excludedManager.duplicateProfile(currentProfile)
                            } label: {
                                Label("Duplicate Profile", systemImage: "doc.on.doc")
                            }

                            Button {
                                profileToRename = currentProfile
                                renameProfileName = currentProfile.name
                                showingRenameSheet = true
                            } label: {
                                Label("Rename Profile", systemImage: "pencil")
                            }

                            Divider()

                            Button(role: .destructive) {
                                excludedManager.deleteProfile(currentProfile)
                            } label: {
                                Label("Delete Profile", systemImage: "trash")
                            }
                            .disabled(excludedManager.profiles.count <= 1)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Profile Options")
                }
            }

            Divider()

            // List of excluded apps
            if excludedManager.currentProfile?.excludedBundleIDs.isEmpty ?? true {
                VStack(spacing: 12) {
                    Text("No excluded applications")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text("Click the + button below to add applications")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(
                            Array(excludedManager.currentProfile?.excludedBundleIDs ?? []).sorted(),
                            id: \.self
                        ) { bundleID in
                            HStack(spacing: 10) {
                                if let appInfo = getAppInfo(for: bundleID) {
                                    if let icon = appInfo.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(appInfo.name)
                                            .font(.body)
                                        Text(bundleID)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Image(systemName: "app.dashed")
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                        .foregroundStyle(.secondary)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(bundleID)
                                            .font(.body)
                                        Text("Not found")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }

                                Spacer()

                                Button {
                                    excludedManager.removeExclusion(bundleID)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .help("Remove from exclusion list")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.08))
                            .cornerRadius(8)
                        }
                    }
                }
                .frame(maxHeight: 450)
            }

            Divider()

            // Add button
            HStack {
                Button {
                    openApplicationPicker()
                } label: {
                    Label("Add Application", systemImage: "plus.circle.fill")
                        .font(.body)
                }
                .buttonStyle(.borderedProminent)
                .help("Choose an application to exclude")

                Spacer()
            }

            Spacer()
        }
        .padding(20)
        .sheet(isPresented: $showingNewProfileSheet) {
            VStack(spacing: 16) {
                Text("New Profile")
                    .font(.headline)

                TextField("Profile Name", text: $newProfileName)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Cancel") {
                        showingNewProfileSheet = false
                        newProfileName = ""
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Create") {
                        if !newProfileName.isEmpty {
                            excludedManager.createProfile(name: newProfileName)
                            showingNewProfileSheet = false
                            newProfileName = ""
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newProfileName.isEmpty)
                }
            }
            .padding(20)
            .frame(width: 300)
        }
        .sheet(isPresented: $showingRenameSheet) {
            VStack(spacing: 16) {
                Text("Rename Profile")
                    .font(.headline)

                TextField("Profile Name", text: $renameProfileName)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Cancel") {
                        showingRenameSheet = false
                        renameProfileName = ""
                        profileToRename = nil
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Rename") {
                        if !renameProfileName.isEmpty, let profile = profileToRename {
                            excludedManager.renameProfile(profile, to: renameProfileName)
                            showingRenameSheet = false
                            renameProfileName = ""
                            profileToRename = nil
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(renameProfileName.isEmpty)
                }
            }
            .padding(20)
            .frame(width: 300)
        }
    }

    private func openApplicationPicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose Application to Exclude"
        panel.message = "Select an application to exclude from the running apps list"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        panel.begin { response in
            guard response == .OK else { return }

            for url in panel.urls {
                if let bundle = Bundle(url: url),
                    let bundleID = bundle.bundleIdentifier
                {
                    excludedManager.addExclusion(bundleID)
                }
            }
        }
    }

    private func getAppInfo(for bundleID: String) -> (name: String, icon: NSImage?)? {
        // First check running apps
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleID
        }) {
            return (app.localizedName ?? bundleID, app.icon)
        }

        // Then check installed apps
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
            let bundle = Bundle(url: url)
        {
            let name =
                bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundleID
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return (name, icon)
        }

        return nil
    }
}

// MARK: - Timeout Controls Sub-View
struct TimeoutControlsView: View {
    @Binding var timeout: TimeInterval
    let minimumValue: TimeInterval
    
    var body: some View {
        HStack(spacing: 16) {
            // Hours control
            HStack(spacing: 8) {
                Text("Hours:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 45, alignment: .trailing)
                
                TextField("0", value: Binding(
                    get: { Int(timeout) / 3600 },
                    set: { newHours in
                        let currentMinutes = (Int(timeout) % 3600) / 60
                        let newTotal = newHours * 3600 + currentMinutes * 60
                        timeout = TimeInterval(max(Int(minimumValue), newTotal))
                    }
                ), formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                    .multilineTextAlignment(.center)
                
                Stepper("", value: Binding(
                    get: { Int(timeout) / 3600 },
                    set: { newHours in
                        let currentMinutes = (Int(timeout) % 3600) / 60
                        let newTotal = newHours * 3600 + currentMinutes * 60
                        timeout = TimeInterval(max(Int(minimumValue), newTotal))
                    }
                ), in: 0...10)
                .labelsHidden()
            }
            
            // Minutes control
            HStack(spacing: 8) {
                Text("Minutes:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 55, alignment: .trailing)
                
                TextField("0", value: Binding(
                    get: { (Int(timeout) % 3600) / 60 },
                    set: { newMinutes in
                        let currentHours = Int(timeout) / 3600
                        let newTotal = currentHours * 3600 + newMinutes * 60
                        timeout = TimeInterval(max(Int(minimumValue), newTotal))
                    }
                ), formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                    .multilineTextAlignment(.center)
                
                Stepper("", value: Binding(
                    get: { (Int(timeout) % 3600) / 60 },
                    set: { newMinutes in
                        let currentHours = Int(timeout) / 3600
                        let newTotal = currentHours * 3600 + newMinutes * 60
                        timeout = TimeInterval(max(Int(minimumValue), newTotal))
                    }
                ), in: 0...59)
                .labelsHidden()
            }
        }
    }
}

// MARK: - App Timeout Row Sub-View
struct AppTimeoutRowView: View {
    let bundleID: String
    let isExcluded: Bool
    let timeout: TimeInterval?
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            if let appInfo = getAppInfo(for: bundleID) {
                if let icon = appInfo.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .opacity(isExcluded ? 0.8 : 1.0)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(appInfo.name)
                        .font(.body)
                        .foregroundColor(isExcluded ? .yellow : .primary)
                    
                    Text(bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
                    .opacity(isExcluded ? 0.8 : 1.0)
                
                Text(bundleID)
                    .font(.body)
                    .foregroundColor(isExcluded ? .yellow : .primary)
            }
            
            Spacer()
            
            timeoutBadge
            
            if !isExcluded && timeout != nil {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Remove custom timeout")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isExcluded ? Color.yellow.opacity(0.05) : Color.gray.opacity(0.08))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private var timeoutBadge: some View {
        if isExcluded {
            Text("excluded")
                .font(.caption)
                .foregroundStyle(.yellow)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.yellow.opacity(0.15))
                .cornerRadius(6)
        } else if let timeout = timeout {
            if timeout == 0 {
                Text("never")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
            } else {
                Text(formatTimeoutBadge(timeout))

                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
            }
        } else {
            Text("default")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
        }
    }
    
    private func getAppInfo(for bundleID: String) -> (name: String, icon: NSImage?)? {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: appURL.path)
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            return (name, icon)
        }
        return nil
    }
    
    private func formatTimeoutBadge(_ timeout: TimeInterval) -> String {
        let hours = Int(timeout) / 3600
        let minutes = (Int(timeout) % 3600) / 60
        
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
}

struct AutoQuitTabView: View {
    @ObservedObject private var autoQuitManager = AutoQuitManager.shared
    @ObservedObject private var excludedManager = ExcludedAppsManager.shared
    @State private var showingAddAppSheet = false
    @State private var selectedBundleID: String?
    @State private var customTimeout: TimeInterval = 300
    
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            leftSettingsSection
            Divider()
            rightAppListSection
        }
        .padding(20)
        .sheet(isPresented: $showingAddAppSheet) {
            customTimeoutSheet
        }
    }
    
    // MARK: - Left Settings Section
    private var leftSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
                Text("Auto-Quit Settings")
                    .font(.headline)
                
                Text("All running apps will be auto-quit after the default timeout. Set custom timeouts for specific apps, or set to 0 to never quit.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Divider()
                
                // Enable/Disable toggle
                Toggle("Enable Auto-Quit", isOn: $autoQuitManager.isEnabled)
                    .toggleStyle(.switch)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                // Respect Exclude Apps toggle
                if autoQuitManager.isEnabled {
                    Toggle("Respect Exclude Apps", isOn: $autoQuitManager.respectExcludeApps)
                        .toggleStyle(.switch)
                        .font(.subheadline)
                        .padding(.leading, 20)
                    
                    Text("When enabled, apps in the exclude list won't be auto-quit")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 20)
                }
                
                // Exclude Profile selector
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Exclude Profile:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Picker(
                            "",
                            selection: Binding(
                                get: {
                                    excludedManager.selectedProfileID ?? excludedManager.profiles.first?.id ?? UUID()
                                },
                                set: { excludedManager.selectedProfileID = $0 }
                            )
                        ) {
                            ForEach(excludedManager.profiles) { profile in
                                Text(profile.name).tag(profile.id)
                            }
                        }
                        .frame(maxWidth: 200)
                        
                        Spacer()
                    }
                    
                    if let profile = excludedManager.currentProfile {
                        Text("\(profile.excludedBundleIDs.count) app\(profile.excludedBundleIDs.count == 1 ? "" : "s") excluded from auto-quit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if autoQuitManager.isEnabled {
                    defaultTimeoutSection
                    .padding(.leading, 20)
                    
                    activeTimersStatusSection
                }
                
                Spacer()
            }
            .frame(width: 400)
    }
    
    // MARK: - Right App List Section
    private var rightAppListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                    Text(autoQuitManager.respectExcludeApps ? "Per-App Timeouts & Excluded Apps" : "Per-App Timeouts")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if autoQuitManager.respectExcludeApps {
                        Text("All apps use default timeout unless listed below. Set timeout to 0 to never quit. Excluded apps won't be auto-quit.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("All apps use default timeout unless listed below. Set timeout to 0 to never quit.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            
            ScrollView {
                VStack(spacing: 6) {
                    let customTimeoutApps = autoQuitManager.appTimeouts.keys.sorted()
                    // Only include excluded apps if respectExcludeApps is enabled
                    let excludedApps = autoQuitManager.respectExcludeApps ? Array(ExcludedAppsManager.shared.excludedBundleIDs).sorted() : []
                    let allBundleIDs = Set(customTimeoutApps + excludedApps).sorted()
                    
                    if allBundleIDs.isEmpty {
                        VStack(spacing: 12) {
                            Text("No custom timeouts\(autoQuitManager.respectExcludeApps ? " or exclusions" : "")")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            
                            Text("Add custom timeouts\(autoQuitManager.respectExcludeApps ? " or excluded apps" : "") to see them here")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(allBundleIDs, id: \.self) { bundleID in
                            let isExcluded = ExcludedAppsManager.shared.isExcluded(bundleID)
                            let timeout = autoQuitManager.appTimeouts[bundleID]
                            
                            AppTimeoutRowView(
                                bundleID: bundleID,
                                isExcluded: isExcluded,
                                timeout: timeout
                            ) {
                                autoQuitManager.removeTimeout(for: bundleID)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 500)
            
            // Add button
            HStack {
                Button {
                    openApplicationPicker()
                } label: {
                    Label("Add App Timeout", systemImage: "plus.circle.fill")
                        .font(.body)
                }
                .buttonStyle(.borderedProminent)
                .help("Set a custom timeout for an app")
                
                Spacer()
            }
            
            Spacer()
        }
        .frame(minWidth: 350)
    }
    
    // MARK: - Default Timeout Section
    private var defaultTimeoutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Default Quit Timeout")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                TimeoutControlsView(
                    timeout: $autoQuitManager.defaultTimeout,
                    minimumValue: 60
                )
                
                Text("Quit apps after this period of inactivity (minimum 1 minute)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    // MARK: - Active Timers Status Section
    private var activeTimersStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.caption)
                    .foregroundStyle(autoQuitManager.activeTimersCount > 0 ? .green : .secondary)
                
                Text("Active Timers:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("\(autoQuitManager.activeTimersCount)")
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fontWeight(.medium)
                
                Text(autoQuitManager.activeTimersCount == 1 ? "app" : "apps")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 20)
            
            if let lastActivity = autoQuitManager.lastActivityTime {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("Last Activity:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(formatLastCheckTime(lastActivity))
                        .font(.caption)
                        .foregroundStyle(.primary)
                    
                    Text("(\(timeAgoString(from: lastActivity)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.leading, 20)
            }
            
            Button {
                printDebugInfo()
            } label: {
                Label("Show Debug Info", systemImage: "ant.circle")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.leading, 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Event-driven: timers trigger precisely when apps reach timeout")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                
                Text("Check Console.app for detailed logs (search for 'QuIt' or '⏰')")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 20)
        }
    }
    
    // MARK: - Custom Timeout Sheet
    private var customTimeoutSheet: some View {
        VStack(spacing: 16) {
            VStack(spacing: 16) {
                Text("Set Custom Timeout")
                    .font(.headline)
                
                if let bundleID = selectedBundleID,
                   let appInfo = getAppInfo(for: bundleID) {
                    HStack(spacing: 12) {
                        if let icon = appInfo.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 48, height: 48)
                        }
                        
                        VStack(alignment: .leading) {
                            Text(appInfo.name)
                                .font(.headline)
                            Text(bundleID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    // Never quit toggle
                    Toggle(isOn: Binding(
                        get: { customTimeout == 0 },
                        set: { isNever in
                            if isNever {
                                customTimeout = 0
                            } else {
                                customTimeout = 300 // Default to 5 minutes when turning off "never"
                            }
                        }
                    )) {
                        HStack(spacing: 6) {
                            Text("Never quit this app")
                                .font(.subheadline)
                            
                            if customTimeout == 0 {
                                Image(systemName: "infinity.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                    
                    if customTimeout > 0 {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Timeout Duration")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            TimeoutControlsView(
                                timeout: $customTimeout,
                                minimumValue: 60
                            )
                            
                            Text("Minimum 1 minute when not set to \"Never\"")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                
                HStack {
                    Button("Cancel") {
                        showingAddAppSheet = false
                        selectedBundleID = nil
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Button("Set") {
                        if let bundleID = selectedBundleID {
                            autoQuitManager.setTimeout(for: bundleID, timeout: customTimeout)
                            showingAddAppSheet = false
                            selectedBundleID = nil
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 420)
        }
    }
    
    private func printDebugInfo() {
        let focusTracker = AppFocusTracker.shared
        let excludedManager = ExcludedAppsManager.shared
        
        print("\n" + String(repeating: "=", count: 60))
        print("🐛 AUTO-QUIT DEBUG INFO")
        print(String(repeating: "=", count: 60))
        
        print("\n📊 Configuration:")
        print("  ✓ Auto-Quit Enabled: \(autoQuitManager.isEnabled)")
        print("  ✓ Respect Exclude Apps: \(autoQuitManager.respectExcludeApps)")
        print("  ✓ Default Timeout: \(Int(autoQuitManager.defaultTimeout))s (\(Int(autoQuitManager.defaultTimeout/60))m)")
        print("  ✓ Custom Timeouts: \(autoQuitManager.appTimeouts.count)")
        print("  ✓ Active Timers: \(autoQuitManager.activeTimersCount)")
        print("  ✓ Excluded Apps: \(excludedManager.excludedBundleIDs.count)")
        
        print("\n📱 Running Apps:")
        let currentPID = NSRunningApplication.current.processIdentifier
        let eligibleApps = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != currentPID && $0.activationPolicy == .regular
        }
        
        for app in eligibleApps {
            guard let bundleID = app.bundleIdentifier else { continue }
            let appName = app.localizedName ?? bundleID
            let isActive = app.isActive ? "✅ ACTIVE" : "⏸️  INACTIVE"
            let isExcluded = excludedManager.isExcluded(bundleID)
            let timeout = autoQuitManager.getTimeout(for: bundleID)
            
            print("  • \(appName)")
            print("      Status: \(isActive)")
            print("      Bundle: \(bundleID)")
            print("      Excluded: \(isExcluded ? "YES ⚠️" : "NO")")
            
            let willBeSkipped = (isExcluded && autoQuitManager.respectExcludeApps) || timeout == 0
            
            if timeout == 0 {
                print("      Timeout: NEVER (0s) ⏭️")
            } else {
                print("      Timeout: \(Int(timeout))s (\(Int(timeout/60))m)")
            }
            
            if willBeSkipped {
                if isExcluded && autoQuitManager.respectExcludeApps {
                    print("      Will Be Auto-Quit: NO (excluded)")
                } else {
                    print("      Will Be Auto-Quit: NO (timeout=0)")
                }
            } else {
                print("      Will Be Auto-Quit: YES")
            }
            
            if let lastFocus = focusTracker.getLastFocusTime(for: bundleID) {
                let inactive = Date().timeIntervalSince(lastFocus)
                print("      Last Focus: \(Int(inactive))s ago")
                
                if willBeSkipped {
                    print("      Will Quit In: NEVER")
                } else {
                    print("      Will Quit In: \(max(0, Int(timeout - inactive)))s")
                }
            } else {
                print("      Last Focus: NONE ⚠️")
            }
            print()
        }
        
        print(String(repeating: "=", count: 60))
        print("💡 Tips:")
        print("  - If 'Last Focus: NONE', switch to that app once to track it")
        print("  - Check Console.app for real-time logs")
        print("  - Look for '⏰' emoji in logs to see timer events")
        print(String(repeating: "=", count: 60) + "\n")
    }
    
    private func formatInterval(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes < 60 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours) hour\(hours == 1 ? "" : "s")"
            } else {
                return "\(hours)h \(remainingMinutes)m"
            }
        }
    }
    
    private func openApplicationPicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose Application for Custom Timeout"
        panel.message = "Select an application to set a custom auto-quit timeout"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        panel.begin { response in
            guard response == .OK else { return }
            
            if let url = panel.urls.first,
               let bundle = Bundle(url: url),
               let bundleID = bundle.bundleIdentifier {
                selectedBundleID = bundleID
                customTimeout = autoQuitManager.getTimeout(for: bundleID)
                showingAddAppSheet = true
            }
        }
    }
    
    private func getAppInfo(for bundleID: String) -> (name: String, icon: NSImage?)? {
        // First check running apps
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleID
        }) {
            return (app.localizedName ?? bundleID, app.icon)
        }
        
        // Then check installed apps
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url) {
            let name =
                bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundleID
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return (name, icon)
        }
        
        return nil
    }
    
    private func formatLastCheckTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

struct FocusTrackingTabView: View {
    @ObservedObject private var focusTracker = AppFocusTracker.shared
    @State private var focusTimesArray: [(bundleID: String, time: Date)] = []
    @State private var refreshTrigger = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("App Focus Tracking")
                .font(.headline)
            
            Text("This tracks the last time each application was focused. Data is used for auto-quit features.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Divider()
            
            HStack {
                Text("\(focusTimesArray.count) apps tracked")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button {
                    refreshData()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")
                
                Button(role: .destructive) {
                    focusTracker.clearAllFocusTimes()
                    refreshData()
                } label: {
                    Label("Clear All", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Clear all focus tracking data")
            }
            
            Divider()
            
            if focusTimesArray.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    
                    Text("No focus data yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    
                    Text("Focus tracking starts automatically when apps become active")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 60)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(focusTimesArray, id: \.bundleID) { item in
                            HStack(spacing: 12) {
                                if let appInfo = getAppInfo(for: item.bundleID) {
                                    if let icon = appInfo.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(appInfo.name)
                                            .font(.body)
                                        Text(item.bundleID)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Image(systemName: "app.dashed")
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                        .foregroundStyle(.secondary)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.bundleID)
                                            .font(.body)
                                    }
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(timeAgoString(from: item.time))
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                    Text(formattedDate(item.time))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Button {
                                    focusTracker.clearFocusTime(for: item.bundleID)
                                    refreshData()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove this entry")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.gray.opacity(0.08))
                            .cornerRadius(8)
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
            
            Spacer()
        }
        .padding(20)
        .onAppear {
            refreshData()
        }
    }
    
    private func refreshData() {
        let allTimes = focusTracker.getAllFocusTimes()
        focusTimesArray = allTimes.map { (bundleID: $0.key, time: $0.value) }
            .sorted { $0.time > $1.time }  // Most recent first
        refreshTrigger.toggle()
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min\(minutes == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func getAppInfo(for bundleID: String) -> (name: String, icon: NSImage?)? {
        // First check running apps
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleID
        }) {
            return (app.localizedName ?? bundleID, app.icon)
        }

        // Then check installed apps
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
            let bundle = Bundle(url: url)
        {
            let name =
                bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundleID
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return (name, icon)
        }

        return nil
    }
}

#Preview {
    ContentView()
        .frame(width: 300)
}
