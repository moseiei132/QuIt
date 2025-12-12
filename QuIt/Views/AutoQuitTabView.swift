//
//  AutoQuitTabView.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Make String identifiable for sheet(item:)
extension String: @retroactive Identifiable {
    public var id: String { self }
}

struct AutoQuitTabView: View {
    @ObservedObject private var autoQuitManager = AutoQuitManager.shared
    @ObservedObject private var excludedManager = ExcludedAppsManager.shared
    // selectedBundleID is used as the sheet item - when non-nil, sheet shows
    @State private var showingActiveTimersSheet = false
    @State private var selectedBundleID: String?
    @State private var customTimeout: TimeInterval = 300
    @StateObject private var runningAppsModel = RunningAppsModel()
    @State private var showingAddAppSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Description
                Text("Automatically quit inactive apps after a configured timeout period.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

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

                    // Per-App Timeouts
                    perAppTimeoutsSection

                    // Status & Monitoring
                    statusMonitoringGroup
                }

                Spacer()
            }
            .padding(20)
        }
        .sheet(item: $selectedBundleID) { bundleID in
            customTimeoutSheet(for: bundleID)
        }
        .sheet(isPresented: $showingActiveTimersSheet) {
            activeTimersSheet
        }
        .sheet(isPresented: $showingAddAppSheet) {
            AddAppSheet(showingSheet: $showingAddAppSheet, runningAppsModel: runningAppsModel) {
                app in
                if let bundleId = app.bundleIdentifier {
                    customTimeout = autoQuitManager.getTimeout(for: bundleId)
                    selectedBundleID = bundleId
                }
            }
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

                            Picker(
                                "",
                                selection: Binding(
                                    get: {
                                        excludedManager.selectedProfileID ?? excludedManager
                                            .profiles.first?.id ?? UUID()
                                    },
                                    set: { excludedManager.selectedProfileID = $0 }
                                )
                            ) {
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

                                    Text(
                                        "\(profile.excludedBundleIDs.count) app\(profile.excludedBundleIDs.count == 1 ? "" : "s") excluded"
                                    )
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
                            .foregroundStyle(
                                autoQuitManager.activeTimersCount > 0 ? .green : .secondary)

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

                        // Show Active Timers button
                        if autoQuitManager.activeTimersCount > 0 {
                            Button {
                                showingActiveTimersSheet = true
                            } label: {
                                Image(systemName: "eye")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Show apps with active timers")
                        }
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

                }
            }
            .padding(10)
        }
    }

    // MARK: - Per-App Timeouts Section
    private var perAppTimeoutsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Label(
                        autoQuitManager.respectExcludeApps
                            ? "Per-App Timeouts & Exclusions" : "Per-App Timeouts",
                        systemImage: "app.badge.checkmark"
                    )
                    .font(.subheadline)
                    .fontWeight(.semibold)

                    Spacer()

                    // Add button
                    Button {
                        runningAppsModel.reload()
                        showingAddAppSheet = true
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
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if autoQuitManager.respectExcludeApps {
                    Text("Custom timeouts override the default. Excluded apps won't be auto-quit.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Custom timeouts override the default. Set to 0 to never quit.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                // App List
                let customTimeoutApps = autoQuitManager.appTimeouts.keys.sorted()
                let excludedApps =
                    autoQuitManager.respectExcludeApps
                    ? Array(ExcludedAppsManager.shared.excludedBundleIDs).sorted() : []
                let allBundleIDs = Set(customTimeoutApps + excludedApps).sorted()

                if allBundleIDs.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
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
                    .frame(maxHeight: 300)
                }
            }
            .padding(10)
        }
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

                Text(
                    "Click the + button above to add custom timeouts\(autoQuitManager.respectExcludeApps ? " or manage exclusions in the Exclude Apps tab" : "")"
                )
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
    private func customTimeoutSheet(for bundleID: String) -> some View {
        let appInfo = getAppInfo(for: bundleID)

        return VStack(spacing: 20) {
            // Header
            VStack(spacing: 12) {
                Text("Set Custom Timeout")
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 12) {
                    if let icon = appInfo?.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 56, height: 56)
                            .cornerRadius(8)
                    } else {
                        Image(systemName: "app.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                            .frame(width: 56, height: 56)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(appInfo?.name ?? bundleID)
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

            Divider()

            // Settings
            VStack(alignment: .leading, spacing: 16) {
                // Never quit toggle
                GroupBox {
                    Toggle(
                        isOn: Binding(
                            get: { customTimeout == 0 },
                            set: { isNever in
                                if isNever {
                                    customTimeout = 0
                                } else {
                                    customTimeout = 300
                                }
                            }
                        )
                    ) {
                        HStack(spacing: 8) {
                            Image(
                                systemName: customTimeout == 0
                                    ? "infinity.circle.fill" : "infinity.circle"
                            )
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
                    selectedBundleID = nil
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)

                Spacer()

                Button("Set Timeout") {
                    autoQuitManager.setTimeout(for: bundleID, timeout: customTimeout)
                    selectedBundleID = nil
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    // MARK: - Active Timers Sheet
    private var activeTimersSheet: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Active Timers")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(
                        "\(autoQuitManager.activeTimersCount) app\(autoQuitManager.activeTimersCount == 1 ? "" : "s") will be auto-quit when inactive"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showingActiveTimersSheet = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Apps list
            ScrollView {
                VStack(spacing: 8) {
                    let activeBundleIDs = autoQuitManager.getActiveTimerBundleIDs()

                    if activeBundleIDs.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "timer.slash")
                                .font(.system(size: 48))
                                .foregroundStyle(.tertiary)

                            Text("No Active Timers")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            Text("Apps will appear here when they become inactive")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(activeBundleIDs.sorted(), id: \.self) { bundleID in
                            activeTimerRow(bundleID: bundleID)
                        }
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 400)
        }
        .padding(24)
        .frame(width: 500)
    }

    private func activeTimerRow(bundleID: String) -> some View {
        let focusTracker = AppFocusTracker.shared
        let appInfo = getAppInfo(for: bundleID)
        let timeout = autoQuitManager.getTimeout(for: bundleID)

        let timeRemaining: TimeInterval = {
            guard let lastFocusTime = focusTracker.getLastFocusTime(for: bundleID) else {
                return 0
            }
            let elapsed = Date().timeIntervalSince(lastFocusTime)
            return max(0, timeout - elapsed)
        }()

        return HStack(spacing: 12) {
            // App icon
            if let icon = appInfo?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
            } else {
                Image(systemName: "app")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }

            // App name and bundle ID
            VStack(alignment: .leading, spacing: 2) {
                Text(appInfo?.name ?? bundleID)
                    .font(.body)
                    .fontWeight(.medium)

                Text(bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Time remaining
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatTimeRemaining(timeRemaining))
                    .font(.headline)
                    .foregroundColor(
                        timeRemaining < 60 ? .red : (timeRemaining < 300 ? .orange : .green))

                Text("remaining")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return secs > 0 ? "\(minutes)m \(secs)s" : "\(minutes)m"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        } else {
            let days = Int(seconds / 86400)
            return "\(days)d"
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
        print("  ✓ Only Custom Timeouts: \(autoQuitManager.onlyCustomTimeouts)")
        print(
            "  ✓ Default Timeout: \(Int(autoQuitManager.defaultTimeout))s (\(Int(autoQuitManager.defaultTimeout/60))m)"
        )
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

            let willBeSkipped =
                (isExcluded && autoQuitManager.respectExcludeApps)
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
                let bundleID = bundle.bundleIdentifier
            {
                customTimeout = autoQuitManager.getTimeout(for: bundleID)
                selectedBundleID = bundleID
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
