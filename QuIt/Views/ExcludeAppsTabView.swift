//
//  ExcludeAppsTabView.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ExcludeAppsTabView: View {
    @ObservedObject private var excludedManager = ExcludedAppsManager.shared
    @State private var showingNewProfileSheet = false
    @State private var newProfileName = ""
    @State private var showingRenameSheet = false
    @State private var profileToRename: ExclusionProfile?
    @State private var renameProfileName = ""
    @StateObject private var runningAppsModel = RunningAppsModel()
    @State private var showingAddAppSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                    runningAppsModel.reload()
                    showingAddAppSheet = true
                } label: {
                    Label("Add Application", systemImage: "plus.circle.fill")
                        .font(.body)
                }
                .buttonStyle(.borderedProminent)
                .help("Choose an application to exclude")

                Spacer()
            }
            .sheet(isPresented: $showingAddAppSheet) {
                AddAppSheet(showingSheet: $showingAddAppSheet, runningAppsModel: runningAppsModel) {
                    app in
                    if let bundleId = app.bundleIdentifier {
                        excludedManager.addExclusion(bundleId)
                    }
                }
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
