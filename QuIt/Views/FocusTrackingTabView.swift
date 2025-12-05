//
//  FocusTrackingTabView.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import SwiftUI

struct FocusTrackingTabView: View {
    @ObservedObject private var focusTracker = AppFocusTracker.shared
    @State private var focusTimesArray: [(bundleID: String, time: Date)] = []
    @State private var refreshTrigger = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("App Focus Tracking")
                .font(.headline)
            
            Text("This tracks the last time each application was focused. Data is used for auto-quit features.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Divider()
            
            HStack {
                Text("\(focusTimesArray.count) apps tracked")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button {
                    refreshData()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")
                
                Button(role: .destructive) {
                    focusTracker.clearAllFocusTimes()
                    refreshData()
                } label: {
                    Label("Clear All", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Clear all focus tracking data")
            }
            
            Divider()
            
            if focusTimesArray.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    
                    Text("No focus data yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    
                    Text("Focus tracking starts automatically when apps become active")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 60)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(focusTimesArray, id: \.bundleID) { item in
                            HStack(spacing: 12) {
                                if let appInfo = getAppInfo(for: item.bundleID) {
                                    if let icon = appInfo.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(appInfo.name)
                                            .font(.body)
                                        Text(item.bundleID)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Image(systemName: "app.dashed")
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                        .foregroundStyle(.secondary)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.bundleID)
                                            .font(.body)
                                    }
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(timeAgoString(from: item.time))
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                    Text(formattedDate(item.time))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Button {
                                    focusTracker.clearFocusTime(for: item.bundleID)
                                    refreshData()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove this entry")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.gray.opacity(0.08))
                            .cornerRadius(8)
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
            
            Spacer()
        }
        .padding(20)
        .onAppear {
            refreshData()
        }
    }
    
    private func refreshData() {
        let allTimes = focusTracker.getAllFocusTimes()
        focusTimesArray = allTimes.map { (bundleID: $0.key, time: $0.value) }
            .sorted { $0.time > $1.time }  // Most recent first
        refreshTrigger.toggle()
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min\(minutes == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
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

#Preview {
    ContentView()
        .frame(width: 300)
}
