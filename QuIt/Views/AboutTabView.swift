//
//  AboutTabView.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import SwiftUI

struct AboutTabView: View {
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @State private var showBuildInfoPopover = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // App Info
                appInfoSection

                Divider()

                // Links
                linksSection

                Divider()

                // Update Section
                updateSection

                Divider()

                // Permissions
                permissionsSection

                Spacer()
            }
            .padding(20)
        }
    }

    // MARK: - App Info Section
    private var appInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Version:")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text(updateChecker.getCurrentVersion())
                        .font(.callout)
                        .fontWeight(.medium)

                    Text("(\(updateChecker.getCurrentBuildNumber()))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 8) {
                    Text("Build:")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Text(UpdateChecker.BuildInfo.isOfficialBuild ? "Official" : "Unofficial")
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundStyle(
                                UpdateChecker.BuildInfo.isOfficialBuild ? .green : .orange)

                        if !UpdateChecker.BuildInfo.isOfficialBuild {
                            Button {
                                showBuildInfoPopover.toggle()
                            } label: {
                                Image(systemName: "questionmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showBuildInfoPopover) {
                                Text(
                                    "Unofficial builds (self-compiled) cannot use OTA updates due to certificate matching requirements. You must download updates manually from GitHub."
                                )
                                .font(.callout)
                                .padding()
                                .frame(width: 300)
                            }
                        }
                    }
                }

                Text(
                    "QuIt helps you quickly quit multiple applications with smart auto-quit functionality."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Links Section
    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Changelog button
                Button {
                    if let url = URL(string: "https://github.com/moseiei132/QuIt/releases") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                        Text("Changelog")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("View release notes on GitHub")

                // GitHub button
                Button {
                    if let url = URL(string: "https://github.com/moseiei132/QuIt") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        // GitHub icon using SF Symbol
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                        Text("GitHub")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("View project on GitHub")
            }
        }
    }

    // MARK: - Update Section
    private var updateSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Software Update", systemImage: "arrow.down.circle")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    // Auto-check toggle
                    Toggle(
                        "Automatically check for updates",
                        isOn: Binding(
                            get: { updateChecker.autoCheckEnabled },
                            set: { updateChecker.autoCheckEnabled = $0 }
                        )
                    )
                    .font(.subheadline)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Text("QuIt will check for updates daily")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    // Last checked
                    if let lastChecked = updateChecker.lastChecked {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("Last checked: \(formatDate(lastChecked))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Check now button
                    HStack {
                        Button {
                            updateChecker.checkForUpdates()
                        } label: {
                            if updateChecker.isCheckingForUpdates {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .controlSize(.small)
                                    Text("Checking...")
                                }
                            } else {
                                Label(
                                    "Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(updateChecker.isCheckingForUpdates)

                        if updateChecker.updateAvailable {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.orange)

                                Text("Update available")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - Permissions Section
    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permissions")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Automation")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("Required to quit other applications")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notifications")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("Optional - for auto-quit alerts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Text("Configure in: System Settings → Privacy & Security")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Button {
                    if let url = URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy")
                    {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open System Settings", systemImage: "gear")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Helper
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
