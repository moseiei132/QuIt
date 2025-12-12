//
//  AddAppSheet.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AddAppSheet: View {
    @Binding var showingSheet: Bool
    @ObservedObject var runningAppsModel: RunningAppsModel
    var onAdd: (RunningApp) -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Add App")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    showingSheet = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            List {
                Button {
                    selectAppFromFinder()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.title3)
                            .foregroundStyle(.blue)
                            .frame(width: 32)

                        Text("Select from Finder...")
                            .font(.body)

                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)

                Section("Running Apps") {
                    ForEach(runningAppsModel.apps) { app in
                        Button {
                            onAdd(app)
                            showingSheet = false
                        } label: {
                            HStack(spacing: 12) {
                                Image(nsImage: app.icon ?? NSImage())
                                    .resizable()
                                    .frame(width: 32, height: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                        .font(.body)

                                    if let bundleId = app.bundleIdentifier {
                                        Text(bundleId)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(height: 400)
        }
        .padding(24)
        .frame(width: 500)
    }

    private func selectAppFromFinder() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        panel.begin { response in
            if response == .OK, let url = panel.url {
                if let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier {
                    let name =
                        bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                        ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                        ?? url.deletingPathExtension().lastPathComponent

                    let app = RunningApp(
                        id: Int.random(in: 0...99999),
                        bundleIdentifier: bundleId,
                        name: name,
                        icon: NSWorkspace.shared.icon(forFile: url.path),
                        isActive: false,
                        pid: 0,
                        lastFocusTime: nil
                    )
                    onAdd(app)
                    showingSheet = false
                }
            }
        }
    }
}
