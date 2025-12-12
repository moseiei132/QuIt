//
//  AlarmNotificationView.swift
//  QuIt
//
//  Created by Antigravity on 12/12/2568 BE.
//

import SwiftUI

struct AlarmNotificationView: View {
    let profileName: String
    let onSwitch: () -> Void
    let onReject: () -> Void
    let onSnooze: (Int) -> Void  // Takes minutes as parameter

    @State private var showingSnoozeOptions = false

    private let snoozeOptions = [
        (minutes: 5, label: "5 min"),
        (minutes: 10, label: "10 min"),
        (minutes: 15, label: "15 min"),
        (minutes: 30, label: "30 min"),
        (minutes: 60, label: "1 hour"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            // Notification-style header
            HStack(spacing: 12) {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Profile Switch Reminder")
                        .font(.headline)
                        .fontWeight(.semibold)

                    Text("Time to switch to '\(profileName)' profile")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Divider()

            if showingSnoozeOptions {
                // Snooze duration options
                VStack(spacing: 12) {
                    Text("Snooze for:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 8) {
                        ForEach(snoozeOptions, id: \.minutes) { option in
                            Button(action: {
                                onSnooze(option.minutes)
                            }) {
                                HStack {
                                    Image(systemName: "clock.fill")
                                    Text(option.label)
                                    Spacer()
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity)
                                .background(Color.orange.opacity(0.1))
                                .foregroundColor(.orange)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button(action: {
                        showingSnoozeOptions = false
                    }) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(Color.gray.opacity(0.1))
                            .foregroundColor(.primary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

            } else {
                // Main action buttons
                VStack(spacing: 8) {
                    Button(action: onSwitch) {
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Switch to \(profileName)")
                            Spacer()
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 8) {
                        Button(action: onReject) {
                            HStack {
                                Image(systemName: "xmark.circle")
                                Text("Reject")
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            showingSnoozeOptions = true
                        }) {
                            HStack {
                                Image(systemName: "clock.fill")
                                Text("Snooze")
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 350)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
    }
}
