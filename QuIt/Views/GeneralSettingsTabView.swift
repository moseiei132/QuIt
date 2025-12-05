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
    @ObservedObject private var autoQuitManager = AutoQuitManager.shared

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

