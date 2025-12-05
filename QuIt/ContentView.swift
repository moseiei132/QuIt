//
//  ContentView.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import SwiftUI
import AppKit
import Combine

// Model to represent a running app snapshot
struct RunningApp: Identifiable, Hashable {
    // Use pid for uniqueness to avoid duplicate IDs in LazyVStack.
    let id: Int
    let bundleIdentifier: String?
    let name: String
    let icon: NSImage?
    let isActive: Bool
    let pid: pid_t
}

// Notification name for excluded apps changes
extension Notification.Name {
    static let excludedAppsDidChange = Notification.Name("excludedAppsDidChange")
}

// Manager for excluded apps with persistence
class ExcludedAppsManager: ObservableObject {
    static let shared = ExcludedAppsManager()
    
    @Published var excludedBundleIDs: Set<String> {
        didSet {
            save()
            NotificationCenter.default.post(name: .excludedAppsDidChange, object: nil)
        }
    }
    
    private let userDefaultsKey = "excludedApps"
    
    private init() {
        if let savedData = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] {
            excludedBundleIDs = Set(savedData)
        } else {
            excludedBundleIDs = []
        }
    }
    
    private func save() {
        UserDefaults.standard.set(Array(excludedBundleIDs), forKey: userDefaultsKey)
    }
    
    func addExclusion(_ bundleID: String) {
        excludedBundleIDs.insert(bundleID)
    }
    
    func removeExclusion(_ bundleID: String) {
        excludedBundleIDs.remove(bundleID)
    }
    
    func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID = bundleID else { return false }
        return excludedBundleIDs.contains(bundleID)
    }
}

// ViewModel to observe running apps and selection state
@MainActor
final class RunningAppsModel: ObservableObject {
    @Published var apps: [RunningApp] = []
    @Published var selectedIDs: Set<Int> = []
    @Published var lastQuitResult: String? = nil

    private var observers: [Any] = []

    init() {
        // Defer main-actor work until after initialization completes.
        Task { @MainActor in
            self.reload()
        }

        let center = NSWorkspace.shared.notificationCenter

        // Capture a nonisolated function reference that will hop to the main actor.
        let triggerReload = Self.triggerReload

        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            triggerReload(self)
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            triggerReload(self)
        })
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            triggerReload(self)
        })
        
        // Observe exclusion list changes
        observers.append(NotificationCenter.default.addObserver(forName: .excludedAppsDidChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            triggerReload(self)
        })
    }

    deinit {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for obs in observers {
            workspaceCenter.removeObserver(obs)
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // Static helper that safely hops to the main actor to call reload without capturing
    // main-actor isolated self in a @Sendable context.
    nonisolated private static func triggerReload(_ model: RunningAppsModel) {
        Task { @MainActor in
            model.reload()
        }
    }

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
           let info = bundle.infoDictionary {
            if let isUIElement = info["LSUIElement"] as? Bool, isUIElement { return false }
            if let isBackgroundOnly = info["LSBackgroundOnly"] as? Bool, isBackgroundOnly { return false }
        }

        return true
    }

    func reload() {
        let currentPID = NSRunningApplication.current.processIdentifier
        let excludedManager = ExcludedAppsManager.shared
        
        let running = NSWorkspace.shared.runningApplications
            .filter { 
                isForceQuitEligible($0) && 
                $0.processIdentifier != currentPID &&
                !excludedManager.isExcluded($0.bundleIdentifier)
            }
            .map { app -> RunningApp in
                let pid = app.processIdentifier
                let id = Int(pid) // unique per process
                let name = app.localizedName ?? app.bundleIdentifier ?? "PID \(pid)"
                return RunningApp(
                    id: id,
                    bundleIdentifier: app.bundleIdentifier,
                    name: name,
                    icon: app.icon,
                    isActive: app.isActive,
                    pid: pid
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

    // Quit all selected apps using a "VacuumClone-like" approach:
    // - Activate target
    // - Send Quit Apple Event (kAEQuitApplication)
    // - Process sequentially with small delays
    // - Report remaining apps
    func quitSelectedApps() {
        lastQuitResult = "Quitting apps..."

        // Resolve selected pids to NSRunningApplication instances.
        let selectedPIDs = Set(selectedIDs.map(pid_t.init))
        let targets = NSWorkspace.shared.runningApplications.filter { selectedPIDs.contains($0.processIdentifier) }
        
        guard !targets.isEmpty else {
            lastQuitResult = "No apps selected."
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
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s

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
                try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s
            }

            // After a small delay, check which ones are still running and report.
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            let stillRunningPIDs = Set(NSWorkspace.shared.runningApplications.map { $0.processIdentifier })
            let remaining = targets.filter { stillRunningPIDs.contains($0.processIdentifier) }
            
            if remaining.isEmpty {
                lastQuitResult = "✅ Successfully quit \(targets.count) app(s)."
                print("✅ All apps quit successfully")
            } else {
                let names = remaining.compactMap { $0.localizedName ?? $0.bundleIdentifier }.joined(separator: ", ")
                lastQuitResult = "⚠️ Some apps did not quit: \(names)\n(They may have unsaved changes or require permission)"
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

    var body: some View {
        VStack(spacing: 12) {
            // First section: Running applications with checkboxes
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Running Applications")
                        .font(.headline)
                        .opacity(0.9)
                    Spacer()
                    Button {
                        openSettingsWindow()
                    } label: {
                        Image(systemName: "gear")
                            .imageScale(.medium)
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                    
                    Button {
                        model.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .imageScale(.medium)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh")
                }

                if model.apps.isEmpty {
                    Text("No running applications found.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(model.apps) { app in
                                HStack(spacing: 8) {
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

                                    // App name
                                    Text(app.name)
                                        .font(.body)
                                        .lineLimit(1)

                                    Spacer(minLength: 8)

                                    // Checkbox (Toggle style)
                                    Toggle("", isOn: Binding(
                                        get: { model.isSelected(app) },
                                        set: { _ in model.toggle(app) }
                                    ))
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()
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
                    .frame(height: min(240, CGFloat(model.apps.count) * 32 + 12))
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

                    Button {
                        // Example: Print selected app IDs
                        print("Selected apps: \(model.selectedIDs)")
                    } label: {
                        Label("Do Something", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer(minLength: 8)

                    Button(role: .destructive) {
                        NSApp.terminate(nil)
                    } label: {
                        Image(systemName: "power")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Quit QuIt")
                }

                if let result = model.lastQuitResult {
                    Text(result)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        )
        .frame(width: 300)
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
        window.isReleasedWhenClosed = false
        
        // Center on main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowSize = NSSize(width: 500, height: 700)
            let origin = NSPoint(
                x: screenFrame.midX - windowSize.width / 2,
                y: screenFrame.midY - windowSize.height / 2
            )
            window.setFrame(NSRect(origin: origin, size: windowSize), display: true)
        } else {
            window.center()
        }
        
        window.makeKeyAndOrderFront(nil)
        window.level = .floating
        
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
                AboutTabView()
                    .tabItem {
                        Label("About", systemImage: "info.circle")
                    }
                    .tag(0)
                
                ExcludeAppsTabView()
                    .tabItem {
                        Label("Exclude Apps", systemImage: "eye.slash")
                    }
                    .tag(1)
            }
        }
        .frame(width: 500, height: 700)
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
                
                Text("QuIt requires Automation permission to quit other apps. If apps won't quit, check System Settings → Privacy & Security → Automation.")
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
    @State private var availableApps: [(bundleID: String, name: String, icon: NSImage?)] = []
    @State private var searchText = ""
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Excluded Applications")
                .font(.headline)
            
            Text("Applications in this list will not appear in the running apps list.")
                .font(.callout)
                .foregroundStyle(.secondary)
            
            Divider()
            
            // List of excluded apps
            if excludedManager.excludedBundleIDs.isEmpty {
                Text("No excluded applications")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(excludedManager.excludedBundleIDs), id: \.self) { bundleID in
                            HStack(spacing: 8) {
                                if let appInfo = getAppInfo(for: bundleID) {
                                    if let icon = appInfo.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 20, height: 20)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(appInfo.name)
                                            .font(.body)
                                        Text(bundleID)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text(bundleID)
                                        .font(.body)
                                }
                                
                                Spacer()
                                
                                Button {
                                    excludedManager.removeExclusion(bundleID)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .help("Remove from exclusion list")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
            
            Divider()
            
            // Add new exclusion
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Add Application to Exclude")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 20, height: 20)
                    }
                }
                
                TextField("Search applications...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                
                if isLoading && availableApps.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Loading applications...")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 30)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(filteredAvailableApps, id: \.bundleID) { app in
                                HStack(spacing: 8) {
                                    if let icon = app.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 20, height: 20)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(app.name)
                                            .font(.body)
                                        Text(app.bundleID)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    
                                    Spacer()
                                    
                                    if excludedManager.excludedBundleIDs.contains(app.bundleID) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    } else {
                                        Button {
                                            excludedManager.addExclusion(app.bundleID)
                                        } label: {
                                            Image(systemName: "plus.circle.fill")
                                                .foregroundStyle(.blue)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Add to exclusion list")
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.gray.opacity(0.05))
                                .cornerRadius(6)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
            }
        }
        .padding(20)
        .onAppear {
            if availableApps.isEmpty {
                loadAvailableApps()
            }
        }
    }
    
    private var filteredAvailableApps: [(bundleID: String, name: String, icon: NSImage?)] {
        if searchText.isEmpty {
            return availableApps
        }
        return availableApps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText) ||
            app.bundleID.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private func loadAvailableApps() {
        isLoading = true
        
        Task.detached(priority: .userInitiated) {
            var apps: [(bundleID: String, name: String, icon: NSImage?)] = []
            let fileManager = FileManager.default
            
            // Common application directories
            let appDirectories = [
                "/Applications",
                "/System/Applications",
                "/System/Library/CoreServices/Applications",
                "\(NSHomeDirectory())/Applications"
            ]
            
            var foundBundleIDs = Set<String>()
            
            for directory in appDirectories {
                guard let enumerator = fileManager.enumerator(
                    at: URL(fileURLWithPath: directory),
                    includingPropertiesForKeys: [.isDirectoryKey, .isApplicationKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                
                for case let fileURL as URL in enumerator {
                    // Check if it's an app bundle
                    if fileURL.pathExtension == "app" {
                        if let bundle = Bundle(url: fileURL),
                           let bundleID = bundle.bundleIdentifier,
                           !foundBundleIDs.contains(bundleID),
                           bundleID != Bundle.main.bundleIdentifier {
                            
                            foundBundleIDs.insert(bundleID)
                            
                            let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                                ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                                ?? fileURL.deletingPathExtension().lastPathComponent
                            
                            let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
                            
                            apps.append((bundleID, name, icon))
                        }
                        
                        // Don't traverse into app bundles
                        enumerator.skipDescendants()
                    }
                }
            }
            
            // Sort by name
            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            
            await MainActor.run {
                self.availableApps = apps
                self.isLoading = false
            }
        }
    }
    
    private func getAppInfo(for bundleID: String) -> (name: String, icon: NSImage?)? {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            return (app.localizedName ?? bundleID, app.icon)
        }
        
        // Try to get info from installed apps
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url) {
            let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? bundleID
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
