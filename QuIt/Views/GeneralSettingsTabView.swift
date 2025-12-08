//
//  GeneralSettingsTabView.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import ServiceManagement
import SwiftUI

struct GeneralSettingsTabView: View {
    @State private var launchAtLogin: Bool = false
    @State private var showClearLogsAlert: Bool = false
    @ObservedObject private var autoQuitManager = AutoQuitManager.shared
    @ObservedObject private var keepAwakeManager = KeepAwakeManager.shared
    @ObservedObject private var debugLogger = DebugLogger.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Notifications")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Toggle("Notify on Auto-Quit", isOn: $autoQuitManager.notifyOnAutoQuit)
                    .toggleStyle(.switch)

                Text("Show a notification when an app is automatically quit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("System")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Toggle("Keep Mac Awake", isOn: $keepAwakeManager.isEnabled)
                    .toggleStyle(.switch)

                Text("Prevent your Mac from going to sleep while QuIt is running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Debug")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Toggle("Debug Mode", isOn: $debugLogger.isDebugEnabled)
                    .toggleStyle(.switch)

                Text("Enable detailed logging of app activation and auto-quit events.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Open Log File") {
                        if let logURL = debugLogger.getLogFileURL() {
                            NSWorkspace.shared.open(logURL)
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Clear Logs") {
                        showClearLogsAlert = true
                    }
                    .buttonStyle(.bordered)

                    Text("Log size: \(debugLogger.getLogFileSize())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(20)
        .onAppear {
            launchAtLogin = isLaunchAtLoginEnabled()
        }
        .alert("Clear Logs", isPresented: $showClearLogsAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                debugLogger.clearLogs()
            }
        } message: {
            Text("Are you sure you want to delete all debug logs?")
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
