//
//  AutoQuitTabView.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AutoQuitTabView: View {
    @ObservedObject private var autoQuitManager = AutoQuitManager.shared
    @ObservedObject private var excludedManager = ExcludedAppsManager.shared
    @State private var showingAddAppSheet = false
    @State private var selectedBundleID: String?
    @State private var customTimeout: TimeInterval = 300
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leftSettingsSection
            
            Divider()
            
            rightAppListSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        .sheet(isPresented: $showingAddAppSheet) {
            customTimeoutSheet
        }
    }
    
    // MARK: - Left Settings Section
    private var leftSettingsSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                headerSection
                
                // Enable/Disable toggle
                Toggle("Enable Auto-Quit", isOn: $autoQuitManager.isEnabled)
                    .toggleStyle(.switch)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if autoQuitManager.isEnabled {
                    // Behavior Settings
                    behaviorSettingsGroup
                    
                    // Timeout Settings
                    timeoutSettingsGroup
                    
                    // Status & Monitoring
                    statusMonitoringGroup
                }
                
                Spacer()
            }
            .padding(12)
        }
        .frame(minWidth: 320, idealWidth: 360, maxWidth: 380)
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Auto-Quit Settings")
                .font(.headline)
            
            Text("Automatically quit inactive apps after a configured timeout period.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // MARK: - Behavior Settings Group
    private var behaviorSettingsGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Behavior", systemImage: "gearshape.2")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 10) {
                    // Respect Exclude Apps
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Respect Exclude Apps", isOn: $autoQuitManager.respectExcludeApps)
                            .toggleStyle(.switch)
                            .font(.subheadline)
                        
                        Text("Skip apps in the exclude list")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    // Only Custom Timeouts
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Only Custom Timeouts", isOn: $autoQuitManager.onlyCustomTimeouts)
                            .toggleStyle(.switch)
                            .font(.subheadline)
                        
                        Text("Auto-quit only apps with custom timeout settings")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    // Notify on Auto-Quit
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Show Notifications", isOn: $autoQuitManager.notifyOnAutoQuit)
                            .toggleStyle(.switch)
                            .font(.subheadline)
                        
                        Text("Notify when an app is automatically quit")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(10)
        }
    }
    
    // MARK: - Timeout Settings Group
    private var timeoutSettingsGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Timeout Settings", systemImage: "timer")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 10) {
                    // Default Timeout
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Default Quit Timeout")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        TimeoutControlsView(
                            timeout: $autoQuitManager.defaultTimeout,
                            minimumValue: 60
                        )
                        
                        if autoQuitManager.onlyCustomTimeouts {
                            Text("Base value for custom timeouts")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Applied to all apps without custom settings")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    
                    // Exclude Profile
                    if autoQuitManager.respectExcludeApps {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Exclude Profile")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Picker("", selection: Binding(
                                get: {
                                    excludedManager.selectedProfileID ?? excludedManager.profiles.first?.id ?? UUID()
                                },
                                set: { excludedManager.selectedProfileID = $0 }
                            )) {
                                ForEach(excludedManager.profiles) { profile in
                                    Text(profile.name).tag(profile.id)
                                }
                            }
                            .labelsHidden()
                            
                            if let profile = excludedManager.currentProfile {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.shield")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    Text("\(profile.excludedBundleIDs.count) app\(profile.excludedBundleIDs.count == 1 ? "" : "s") excluded")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
    }
    
    // MARK: - Status & Monitoring Group
    private var statusMonitoringGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Status & Monitoring", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 10) {
                    // Active Timers
                    HStack(spacing: 8) {
                        Image(systemName: "timer")
                            .font(.body)
                            .foregroundStyle(autoQuitManager.activeTimersCount > 0 ? .green : .secondary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Active Timers")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 4) {
                                Text("\(autoQuitManager.activeTimersCount)")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                
                                Text(autoQuitManager.activeTimersCount == 1 ? "app" : "apps")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        
                        Spacer()
                    }
                    
                    // Last Activity
                    if let lastActivity = autoQuitManager.lastActivityTime {
                        HStack(spacing: 8) {
                            Image(systemName: "clock")
                                .font(.body)
                                .foregroundStyle(.secondary)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Last Activity")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Text(timeAgoString(from: lastActivity))
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                            }
                            
                            Spacer()
                        }
                    }
                    
                    Divider()
                    
                    // Debug Button
                    Button {
                        printDebugInfo()
                    } label: {
                        Label("Show Debug Info", systemImage: "ant.circle")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    // Debug Tips
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• Event-driven timers fire precisely at timeout")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("• Check Console.app for detailed logs")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(10)
        }
    }
    
    // MARK: - Right App List Section
    private var rightAppListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(autoQuitManager.respectExcludeApps ? "Per-App Timeouts & Exclusions" : "Per-App Timeouts", 
                          systemImage: "app.badge.checkmark")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    // Add button
                    Button {
                        openApplicationPicker()
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .help("Add custom timeout for an app")
                }
                
                if autoQuitManager.onlyCustomTimeouts {
                    Text("Only these apps will be auto-quit. Set to 0 to never quit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if autoQuitManager.respectExcludeApps {
                    Text("Custom timeouts override the default. Excluded apps won't be auto-quit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Custom timeouts override the default. Set to 0 to never quit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            Divider()
            
            // App List
            ScrollView {
                VStack(spacing: 6) {
                    let customTimeoutApps = autoQuitManager.appTimeouts.keys.sorted()
                    let excludedApps = autoQuitManager.respectExcludeApps ? Array(ExcludedAppsManager.shared.excludedBundleIDs).sorted() : []
                    let allBundleIDs = Set(customTimeoutApps + excludedApps).sorted()
                    
                    if allBundleIDs.isEmpty {
                        emptyStateView
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
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .frame(minWidth: 280, idealWidth: 360, maxWidth: .infinity)
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "app.dashed")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            
            VStack(spacing: 8) {
                Text("No Custom Timeouts")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Text("Click the + button above to add custom timeouts\(autoQuitManager.respectExcludeApps ? " or manage exclusions in the Exclude Apps tab" : "")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    
    // MARK: - Custom Timeout Sheet
    private var customTimeoutSheet: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 12) {
                Text("Set Custom Timeout")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if let bundleID = selectedBundleID,
                   let appInfo = getAppInfo(for: bundleID) {
                    HStack(spacing: 12) {
                        if let icon = appInfo.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 56, height: 56)
                                .cornerRadius(8)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appInfo.name)
                                .font(.headline)
                            Text(bundleID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            
            Divider()
            
            // Settings
            VStack(alignment: .leading, spacing: 16) {
                // Never quit toggle
                GroupBox {
                    Toggle(isOn: Binding(
                        get: { customTimeout == 0 },
                        set: { isNever in
                            if isNever {
                                customTimeout = 0
                            } else {
                                customTimeout = 300
                            }
                        }
                    )) {
                        HStack(spacing: 8) {
                            Image(systemName: customTimeout == 0 ? "infinity.circle.fill" : "infinity.circle")
                                .foregroundStyle(customTimeout == 0 ? .green : .secondary)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Never quit this app")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text("App will never be automatically quit")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                }
                
                // Timeout duration
                if customTimeout > 0 {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "timer")
                                    .foregroundStyle(.secondary)
                                
                                Text("Timeout Duration")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            
                            TimeoutControlsView(
                                timeout: $customTimeout,
                                minimumValue: 60
                            )
                            
                            Text("Minimum 1 minute")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            
            Divider()
            
            // Actions
            HStack(spacing: 12) {
                Button("Cancel") {
                    showingAddAppSheet = false
                    selectedBundleID = nil
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)
                
                Spacer()
                
                Button("Set Timeout") {
                    if let bundleID = selectedBundleID {
                        autoQuitManager.setTimeout(for: bundleID, timeout: customTimeout)
                        showingAddAppSheet = false
                        selectedBundleID = nil
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 460)
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
        print("  ✓ Only Custom Timeouts: \(autoQuitManager.onlyCustomTimeouts)")
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
            let hasCustomTimeout = autoQuitManager.hasCustomTimeout(for: bundleID)
            
            print("  • \(appName)")
            print("      Status: \(isActive)")
            print("      Bundle: \(bundleID)")
            print("      Excluded: \(isExcluded ? "YES ⚠️" : "NO")")
            print("      Has Custom Timeout: \(hasCustomTimeout ? "YES" : "NO")")
            
            let willBeSkipped = (isExcluded && autoQuitManager.respectExcludeApps) 
                || timeout == 0 
                || (autoQuitManager.onlyCustomTimeouts && !hasCustomTimeout)
            
            if timeout == 0 {
                print("      Timeout: NEVER (0s) ⏭️")
            } else {
                print("      Timeout: \(Int(timeout))s (\(Int(timeout/60))m)")
            }
            
            if willBeSkipped {
                if isExcluded && autoQuitManager.respectExcludeApps {
                    print("      Will Be Auto-Quit: NO (excluded)")
                } else if timeout == 0 {
                    print("      Will Be Auto-Quit: NO (timeout=0)")
                } else if autoQuitManager.onlyCustomTimeouts && !hasCustomTimeout {
                    print("      Will Be Auto-Quit: NO (only custom timeouts mode)")
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

