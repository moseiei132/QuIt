//
//  AppTimeoutRowView.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import AppKit
import SwiftUI

// Row view for app timeout list
struct AppTimeoutRowView: View {
    let bundleID: String
    let isExcluded: Bool
    let timeout: TimeInterval?
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            if let appInfo = getAppInfo(for: bundleID) {
                if let icon = appInfo.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .opacity(isExcluded ? 0.8 : 1.0)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(appInfo.name)
                        .font(.body)
                        .foregroundColor(isExcluded ? .yellow : .primary)
                    
                    Text(bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
                    .opacity(isExcluded ? 0.8 : 1.0)
                
                Text(bundleID)
                    .font(.body)
                    .foregroundColor(isExcluded ? .yellow : .primary)
            }
            
            Spacer()
            
            timeoutBadge
            
            if !isExcluded && timeout != nil {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Remove custom timeout")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isExcluded ? Color.yellow.opacity(0.05) : Color.gray.opacity(0.08))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private var timeoutBadge: some View {
        if isExcluded {
            Text("excluded")
                .font(.caption)
                .foregroundStyle(.yellow)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.yellow.opacity(0.15))
                .cornerRadius(6)
        } else if let timeout = timeout {
            if timeout == 0 {
                Text("never")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
            } else {
                Text(formatTimeoutBadge(timeout))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
            }
        } else {
            Text("default")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
        }
    }
    
    private func getAppInfo(for bundleID: String) -> (name: String, icon: NSImage?)? {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: appURL.path)
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            return (name, icon)
        }
        return nil
    }
    
    private func formatTimeoutBadge(_ timeout: TimeInterval) -> String {
        let hours = Int(timeout) / 3600
        let minutes = (Int(timeout) % 3600) / 60
        
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
}

