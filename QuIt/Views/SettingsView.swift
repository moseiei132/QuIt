//
//  SettingsView.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case excludeApps = "Exclude Apps"
    case autoQuit = "Auto-Quit"
    case focusTracking = "Focus Tracking"
    case about = "About"

    var id: String { self.rawValue }

    var icon: String {
        switch self {
        case .general:
            return "gearshape"
        case .excludeApps:
            return "eye.slash"
        case .autoQuit:
            return "timer"
        case .focusTracking:
            return "clock"
        case .about:
            return "info.circle"
        }
    }
}

struct SettingsView: View {
    @State private var selectedSection: SettingsSection? = .general

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                NavigationLink(value: section) {
                    Label(section.rawValue, systemImage: section.icon)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 250)
            .listStyle(.sidebar)
        } detail: {
            // Detail View
            Group {
                if let selectedSection = selectedSection {
                    switch selectedSection {
                    case .general:
                        NavigationStack {
                            GeneralSettingsTabView()
                        }
                    case .focusTracking:
                        NavigationStack {
                            FocusTrackingTabView()
                        }
                    case .autoQuit:
                        NavigationStack {
                            AutoQuitTabView()
                        }
                    case .excludeApps:
                        NavigationStack {
                            ExcludeAppsTabView()
                        }
                    case .about:
                        NavigationStack {
                            AboutTabView()
                        }
                    }
                } else {
                    Text("Select a setting")
                        .foregroundColor(.secondary)
                }
            }
            .id(selectedSection)
        }
        .frame(width: 800, height: 700)
    }
}
