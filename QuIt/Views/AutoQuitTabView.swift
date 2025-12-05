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

