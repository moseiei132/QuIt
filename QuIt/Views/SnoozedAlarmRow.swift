//
//  SnoozedAlarmRow.swift
//  QuIt
//
//  Created by Antigravity on 12/12/2568 BE.
//

import SwiftUI

// MARK: - Snoozed Alarm Row

struct SnoozedAlarmRow: View {
    let snooze: SnoozedAlarm
    @ObservedObject private var alarmManager = ProfileAlarmManager.shared
    @State private var timeRemaining: String = ""
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.fill")
                .font(.system(size: 20))
                .foregroundColor(.orange)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(snooze.profileName)
                    .font(.body)
                    .fontWeight(.medium)

                Text(timeRemaining)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                alarmManager.cancelSnooze(snooze)
            }) {
                Text("Cancel")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal, 16)
        .onAppear {
            updateTimeRemaining()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                updateTimeRemaining()
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func updateTimeRemaining() {
        let now = Date()
        let remaining = snooze.snoozeUntil.timeIntervalSince(now)

        if remaining <= 0 {
            timeRemaining = "Triggering now..."
            timer?.invalidate()

            // Remove expired snooze after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.alarmManager.snoozedAlarms.removeAll { $0.id == self.snooze.id }
            }
        } else {
            let minutes = Int(remaining) / 60
            let seconds = Int(remaining) % 60

            if minutes > 0 {
                timeRemaining = "Snoozing for \(minutes)m \(seconds)s"
            } else {
                timeRemaining = "Snoozing for \(seconds)s"
            }
        }
    }
}
