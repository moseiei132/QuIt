//
//  ProfileAlarmManager.swift
//  QuIt
//
//  Created by Antigravity on 12/12/2568 BE.
//

import Combine
import Foundation
import UserNotifications

extension Notification.Name {
    static let profileAlarmTriggered = Notification.Name("profileAlarmTriggered")
}

struct SnoozedAlarm: Codable, Identifiable {
    let id: String  // Notification identifier
    let alarmID: String
    let profileID: String
    let profileName: String
    let snoozeUntil: Date
    let snoozeDuration: Int  // minutes
}

class ProfileAlarmManager: ObservableObject {
    static let shared = ProfileAlarmManager()

    @Published var alarms: [ProfileAlarm] = []
    @Published var snoozedAlarms: [SnoozedAlarm] = []

    private let alarmsKey = "profileAlarms"
    private let snoozedAlarmsKey = "snoozedAlarms"

    private init() {
        loadAlarms()
        loadSnoozedAlarms()
        print(
            "✅ ProfileAlarmManager initialized with \(alarms.count) alarms and \(snoozedAlarms.count) snoozed alarms"
        )
    }

    // MARK: - Persistence

    private func loadAlarms() {
        if let data = UserDefaults.standard.data(forKey: alarmsKey),
            let decoded = try? JSONDecoder().decode([ProfileAlarm].self, from: data)
        {
            alarms = decoded
        }
    }

    private func saveAlarms() {
        if let encoded = try? JSONEncoder().encode(alarms) {
            UserDefaults.standard.set(encoded, forKey: alarmsKey)
            print("💾 Saved \(alarms.count) alarms to UserDefaults")
        }
    }

    private func loadSnoozedAlarms() {
        if let data = UserDefaults.standard.data(forKey: snoozedAlarmsKey),
            let decoded = try? JSONDecoder().decode([SnoozedAlarm].self, from: data)
        {
            // Filter out expired snoozes
            snoozedAlarms = decoded.filter { $0.snoozeUntil > Date() }
            if snoozedAlarms.count != decoded.count {
                saveSnoozedAlarms()  // Clean up expired ones
            }
        }
    }

    private func saveSnoozedAlarms() {
        if let encoded = try? JSONEncoder().encode(snoozedAlarms) {
            UserDefaults.standard.set(encoded, forKey: snoozedAlarmsKey)
            print("💾 Saved \(snoozedAlarms.count) snoozed alarms to UserDefaults")
        }
    }

    // MARK: - Alarm Management

    func addAlarm(_ alarm: ProfileAlarm) {
        alarms.append(alarm)
        alarms.sort { alarm1, alarm2 in
            if let hour1 = alarm1.time.hour, let hour2 = alarm2.time.hour {
                if hour1 != hour2 {
                    return hour1 < hour2
                }
                return (alarm1.time.minute ?? 0) < (alarm2.time.minute ?? 0)
            }
            return false
        }
        saveAlarms()

        if alarm.isEnabled {
            scheduleAlarm(alarm)
        }

        print("➕ Added alarm: \(alarm.formattedTime) → \(alarm.daysOfWeekString)")
    }

    func updateAlarm(_ alarm: ProfileAlarm) {
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
            saveAlarms()

            // Remove old notification
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: ["alarm-\(alarm.id.uuidString)"]
            )

            // Schedule new notification if enabled
            if alarm.isEnabled {
                scheduleAlarm(alarm)
            }

            print("✏️ Updated alarm: \(alarm.formattedTime)")
        }
    }

    func deleteAlarm(_ alarm: ProfileAlarm) {
        alarms.removeAll { $0.id == alarm.id }
        saveAlarms()

        // Remove notification
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["alarm-\(alarm.id.uuidString)"]
        )

        print("🗑️ Deleted alarm: \(alarm.formattedTime)")
    }

    func toggleAlarm(_ alarm: ProfileAlarm) {
        var updatedAlarm = alarm
        updatedAlarm.isEnabled.toggle()
        updateAlarm(updatedAlarm)
    }

    // MARK: - Notification Scheduling

    func scheduleAlarm(_ alarm: ProfileAlarm) {
        guard alarm.isEnabled else { return }

        guard
            let profileName = ExcludedAppsManager.shared.profiles.first(where: {
                $0.id == alarm.targetProfileID
            })?.name
        else {
            print("⚠️ Cannot schedule alarm: profile not found")
            return
        }

        let content = UNMutableNotificationContent()

        if alarm.autoSwitch {
            content.title = "Profile Auto-Switched"
            content.body = "Switched to '\(profileName)' profile"
            content.categoryIdentifier = "PROFILE_SWITCH_AUTO"  // Different category for auto-switch
        } else {
            content.title = "Profile Switch Reminder"
            content.body = "Time to switch to '\(profileName)' profile"
            content.categoryIdentifier = "PROFILE_SWITCH"
        }

        content.sound = .default
        content.userInfo = [
            "alarmID": alarm.id.uuidString,
            "profileID": alarm.targetProfileID.uuidString,
            "profileName": profileName,
            "autoSwitch": alarm.autoSwitch,
        ]

        // Create trigger
        let triggerDateComponents = alarm.time
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: triggerDateComponents,
            repeats: true
        )

        let request = UNNotificationRequest(
            identifier: "alarm-\(alarm.id.uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to schedule alarm: \(error.localizedDescription)")
            } else {
                print("✅ Scheduled alarm: \(alarm.formattedTime) for \(profileName)")
            }
        }
    }

    func rescheduleAllAlarms() {
        // Remove all pending notifications
        let identifiers = alarms.map { "alarm-\($0.id.uuidString)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: identifiers)

        // Schedule all enabled alarms
        for alarm in alarms where alarm.isEnabled {
            scheduleAlarm(alarm)
        }

        print("🔄 Rescheduled all alarms")
    }

    // MARK: - Snooze Handling

    func scheduleSnoozeNotification(
        alarmID: String, profileID: String, profileName: String, minutes: Int
    ) {
        let snoozeID = "snooze-\(UUID().uuidString)"
        let snoozeUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))

        let content = UNMutableNotificationContent()
        content.title = "Profile Switch Reminder (Snoozed)"
        content.body = "Time to switch to '\(profileName)' profile"
        content.sound = .default
        content.categoryIdentifier = "PROFILE_SWITCH"
        content.userInfo = [
            "alarmID": alarmID,
            "profileID": profileID,
            "profileName": profileName,
            "autoSwitch": false,
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(minutes * 60),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: snoozeID,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to schedule snooze: \(error.localizedDescription)")
            } else {
                print("⏰ Snoozed for \(minutes) minutes")

                // Track the snooze
                DispatchQueue.main.async {
                    let snoozedAlarm = SnoozedAlarm(
                        id: snoozeID,
                        alarmID: alarmID,
                        profileID: profileID,
                        profileName: profileName,
                        snoozeUntil: snoozeUntil,
                        snoozeDuration: minutes
                    )
                    self.snoozedAlarms.append(snoozedAlarm)
                    self.saveSnoozedAlarms()
                }
            }
        }
    }

    func cancelSnooze(_ snooze: SnoozedAlarm) {
        // Remove from notification center
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [snooze.id]
        )

        // Remove from our list
        snoozedAlarms.removeAll { $0.id == snooze.id }
        saveSnoozedAlarms()

        print("🗑️ Canceled snooze: \(snooze.profileName)")
    }
}
