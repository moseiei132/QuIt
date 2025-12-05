//
//  SettingsView.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import SwiftUI

struct SettingsView: View {
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Tab View
            TabView(selection: $selectedTab) {
                GeneralSettingsTabView()
                    .tabItem {
                        Label("General", systemImage: "gearshape")
                    }
                    .tag(0)

                AboutTabView()
                    .tabItem {
                        Label("About", systemImage: "info.circle")
                    }
                    .tag(1)

                ExcludeAppsTabView()
                    .tabItem {
                        Label("Exclude Apps", systemImage: "eye.slash")
                    }
                    .tag(2)
                
                AutoQuitTabView()
                    .tabItem {
                        Label("Auto-Quit", systemImage: "timer")
                    }
                    .tag(3)
                
                FocusTrackingTabView()
                    .tabItem {
                        Label("Focus Tracking", systemImage: "clock")
                    }
                    .tag(4)
            }
        }
        .frame(width: 800, height: 700)
    }
}

