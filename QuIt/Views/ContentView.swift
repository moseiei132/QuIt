//
//  ContentView.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import AppKit
import Combine
import SwiftUI

struct ContentView: View {
    @StateObject private var model = RunningAppsModel()
    @ObservedObject private var templateManager = AppTemplateManager.shared
    @ObservedObject private var excludedManager = ExcludedAppsManager.shared
    @ObservedObject private var autoQuitManager = AutoQuitManager.shared
    @ObservedObject private var keepAwakeManager = KeepAwakeManager.shared

    var body: some View {
        VStack(spacing: 12) {
            // First section: Running applications with checkboxes
            VStack(alignment: .leading, spacing: 8) {
                headerSection
                statusSection
                selectAllSection
                appsListSection
            }

            Divider().opacity(0.6)

            footerSection
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        )
        .frame(width: 330)
        .onAppear {
            // Load apps only when popover opens
            model.reload()
            // Auto-select all non-excluded apps after a brief delay
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000)  // 0.05s
                autoSelectAll()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .popoverWillOpen)) { _ in
            // Reload apps list every time popover opens
            model.reload()
            // Auto-select all non-excluded apps after a brief delay
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000)  // 0.05s
                autoSelectAll()
            }
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        HStack(spacing: 0) {
            Text("Running Apps")
                .font(.headline)
                .opacity(0.9)
            Spacer(minLength: 0)

            HStack(spacing: 2) {
                profileMenu
                refreshButton
            }
        }
    }

    private var profileMenu: some View {
        Menu {
            ForEach(excludedManager.profiles) { profile in
                Button {
                    // Only switch if selecting a different profile
                    guard excludedManager.selectedProfileID != profile.id else { return }

                    // Check if all non-excluded apps were selected before switching
                    let wasAllSelected = model.areAllNonExcludedSelected()

                    // Switch profile
                    excludedManager.selectedProfileID = profile.id
                    model.reload()

                    // If all were selected, reselect all with new profile's excluded list
                    if wasAllSelected {
                        autoSelectAll()
                    }
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
    }

    private var refreshButton: some View {
        Button {
            model.reload()
        } label: {
            Image(systemName: "arrow.clockwise")
                .imageScale(.medium)
        }
        .buttonStyle(.plain)
        .help("Refresh")
    }

    // MARK: - Status Section
    private var statusSection: some View {
        HStack(spacing: 12) {
            excludedAppsInfo
            autoQuitStatus
        }
    }

    @ViewBuilder
    private var excludedAppsInfo: some View {
        if let excludedCount = excludedManager.currentProfile?.excludedBundleIDs.count,
            excludedCount > 0
        {
            HStack(spacing: 4) {
                Image(systemName: "eye.slash")
                    .font(.caption2)
                    .foregroundColor(.yellow)
                Text("\(excludedCount) app\(excludedCount == 1 ? "" : "s") excluded")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var autoQuitStatus: some View {
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

    // MARK: - Select All Section
    private var selectAllSection: some View {
        HStack(spacing: 6) {
            Toggle(
                "",
                isOn: Binding(
                    get: { model.areAllNonExcludedSelected() },
                    set: { _ in model.toggleSelectAll() }
                )
            )
            .toggleStyle(.checkbox)
            .labelsHidden()

            Text("Select All")
                .font(.caption)
        }
    }

    // MARK: - Apps List Section
    @ViewBuilder
    private var appsListSection: some View {
        if model.apps.isEmpty {
            Text("No running applications found.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(model.apps) { app in
                        appRow(app)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: min(280, CGFloat(model.apps.count) * 32 + 12))
        }
    }

    private func appRow(_ app: RunningApp) -> some View {
        let isExcluded = model.isExcluded(app)

        return HStack(spacing: 8) {
            // Checkbox
            Toggle(
                "",
                isOn: Binding(
                    get: { model.isSelected(app) },
                    set: { _ in model.toggle(app) }
                )
            )
            .toggleStyle(.checkbox)
            .labelsHidden()

            // Clickable area to focus app
            Button {
                model.focusApp(app)
            } label: {
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
                        .opacity(isExcluded ? 0.6 : 1.0)

                    // App name with time info
                    HStack(spacing: 4) {
                        Text(app.name)
                            .font(.body)
                            .lineLimit(1)
                            .foregroundColor(isExcluded ? .yellow : .primary)

                        // Only show time info for non-excluded apps
                        if !isExcluded, let lastFocusTime = app.lastFocusTime {
                            appTimeInfo(app: app, lastFocusTime: lastFocusTime)
                        }
                    }

                    Spacer(minLength: 8)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private func appTimeInfo(app: RunningApp, lastFocusTime: Date) -> some View {
        if autoQuitManager.isEnabled && !app.isActive, let bundleID = app.bundleIdentifier {
            // Show countdown timer when auto-quit is enabled
            let timeRemaining = timeUntilQuit(bundleID: bundleID, lastFocusTime: lastFocusTime)
            Text(timeUntilQuitString(bundleID: bundleID, lastFocusTime: lastFocusTime))
                .font(.caption2)
                .foregroundColor(timeRemaining < 60 ? .red : .orange)
        } else {
            // Show time ago when auto-quit is disabled or app is active
            Text(timeAgoString(from: lastFocusTime))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Footer Section
    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    model.quitSelectedApps()
                } label: {
                    Label("Quit Apps", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(model.selectedIDs.isEmpty)

                // Quick Open Menu
                if !templateManager.templates.isEmpty {
                    Menu {
                        ForEach(templateManager.templates) { template in
                            Button {
                                templateManager.launch(template: template)
                            } label: {
                                Text(template.name)
                            }
                        }
                    } label: {
                        Label("Open", systemImage: "globe")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("Quick Open Template")
                    .menuIndicator(.hidden)
                }

                // Spacer(minLength: 8)

                Button {
                    keepAwakeManager.isEnabled.toggle()
                } label: {
                    Image(
                        systemName: keepAwakeManager.isEnabled
                            ? "cup.and.saucer.fill" : "moon.zzz.fill"
                    )
                    .foregroundColor(keepAwakeManager.isEnabled ? .green : .secondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(keepAwakeManager.isEnabled ? "Keep Awake: On" : "Keep Awake: Off")

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

    private func autoSelectAll() {
        // Select all non-excluded apps
        let excludedManager = ExcludedAppsManager.shared
        model.selectedIDs = Set(
            model.apps.filter { !excludedManager.isExcluded($0.bundleIdentifier) }.map { $0.id })
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

    private func timeUntilQuit(bundleID: String, lastFocusTime: Date) -> TimeInterval {
        // Get the timeout for this app
        let timeout = autoQuitManager.getTimeout(for: bundleID)

        // Check if timeout is 0 (never quit)
        if timeout == 0 {
            return .infinity
        }

        // Check if app should be skipped due to settings
        let excludedManager = ExcludedAppsManager.shared
        if autoQuitManager.respectExcludeApps && excludedManager.isExcluded(bundleID) {
            return .infinity
        }

        if autoQuitManager.onlyCustomTimeouts && !autoQuitManager.hasCustomTimeout(for: bundleID) {
            return .infinity
        }

        // Calculate time remaining
        let timeSinceLastFocus = Date().timeIntervalSince(lastFocusTime)
        let timeRemaining = max(0, timeout - timeSinceLastFocus)

        return timeRemaining
    }

    private func timeUntilQuitString(bundleID: String, lastFocusTime: Date) -> String {
        let timeRemaining = timeUntilQuit(bundleID: bundleID, lastFocusTime: lastFocusTime)

        // Check if app will never be quit
        if timeRemaining == .infinity {
            return "Never"
        }

        // Format countdown
        if timeRemaining < 60 {
            return "\(Int(timeRemaining))s left"
        } else if timeRemaining < 3600 {
            let minutes = Int(timeRemaining / 60)
            return "\(minutes)m left"
        } else if timeRemaining < 86400 {
            let hours = Int(timeRemaining / 3600)
            let minutes = Int((timeRemaining.truncatingRemainder(dividingBy: 3600)) / 60)
            if minutes > 0 {
                return "\(hours)h \(minutes)m left"
            } else {
                return "\(hours)h left"
            }
        } else {
            let days = Int(timeRemaining / 86400)
            return "\(days)d left"
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

        let window = SettingsWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]

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

        // Activate the app to ensure the window receives focus
        NSApp.activate(ignoringOtherApps: true)

        // Keep a reference
        WindowManager.shared.settingsWindow = window
    }
}

// Custom NSWindow subclass that cleans up on close
class SettingsWindow: NSWindow {
    override func close() {
        print("🗑️ Settings window closing - cleaning up reference and freeing memory")
        // Clean up the reference BEFORE closing to avoid issues
        WindowManager.shared.settingsWindow = nil
        super.close()
    }

    deinit {
        print("✅ Settings window deallocated - memory freed")
    }
}

// Singleton to manage windows
class WindowManager {
    static let shared = WindowManager()
    var settingsWindow: NSWindow?

    private init() {}
}
