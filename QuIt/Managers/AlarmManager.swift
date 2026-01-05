//
//  AlarmManager.swift
//  QuIt
//
//  Created by Antigravity on 04/01/2569 BE.
//

import Combine
import Foundation
import UserNotifications

extension Notification.Name {
    static let alarmTriggered = Notification.Name("alarmTriggered")
}

class AlarmManager: ObservableObject {
    static let shared = AlarmManager()

    @Published var alarms: [Alarm] = []
    @Published var snoozedAlarms: [SnoozedAlarm] = []
    
    private var alarmCheckTimer: Timer?
    private var lastCheckedMinute: Int?

    private let alarmsKey = "alarms"
    private let snoozedAlarmsKey = "snoozedAlarms"
    
    // Legacy key for migration
    private let legacyAlarmsKey = "profileAlarms"

    private init() {
        migrateOldAlarms()
        loadAlarms()
        loadSnoozedAlarms()
        startAlarmCheckTimer()
    }
    
    deinit {
        alarmCheckTimer?.invalidate()
    }
    
    // MARK: - Background Timer
    
    private func startAlarmCheckTimer() {
        scheduleNextAlarmCheck()
    }
    
    private func scheduleNextAlarmCheck() {
        alarmCheckTimer?.invalidate()
        
        guard let nextAlarmTime = calculateNextAlarmTime() else {
            // No alarms, check again in an hour
            alarmCheckTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: false) { [weak self] _ in
                self?.scheduleNextAlarmCheck()
            }
            return
        }
        
        let now = Date()
        let timeInterval = nextAlarmTime.timeIntervalSince(now)
        
        if timeInterval <= 0 {
            // Alarm is now or past, execute immediately
            executeCurrentAlarms()
            // Schedule next check
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.scheduleNextAlarmCheck()
            }
        } else {
            // Schedule timer for exact alarm time
            print("⏰ Next alarm scheduled in \(Int(timeInterval)) seconds")
            alarmCheckTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
                self?.executeCurrentAlarms()
                // Schedule next alarm
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self?.scheduleNextAlarmCheck()
                }
            }
        }
    }
    
    private func calculateNextAlarmTime() -> Date? {
        let now = Date()
        let calendar = Calendar.current
        var nearestAlarmTime: Date?
        
        for alarm in alarms where alarm.isEnabled && alarm.autoExecute {
            guard let hour = alarm.time.hour,
                  let minute = alarm.time.minute else {
                continue
            }
            
            // Try today first
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = hour
            components.minute = minute
            components.second = 0
            
            guard var alarmDate = calendar.date(from: components) else {
                continue
            }
            
            // If alarm time has passed today, try tomorrow and next 7 days
            if alarmDate <= now {
                for dayOffset in 1...7 {
                    guard let futureDate = calendar.date(byAdding: .day, value: dayOffset, to: alarmDate) else {
                        continue
                    }
                    alarmDate = futureDate
                    
                    let weekday = calendar.component(.weekday, from: alarmDate)
                    if alarm.daysOfWeek.isEmpty || alarm.daysOfWeek.contains(weekday) {
                        break
                    }
                }
            } else {
                // Check if today matches day of week requirement
                let weekday = calendar.component(.weekday, from: alarmDate)
                if !alarm.daysOfWeek.isEmpty && !alarm.daysOfWeek.contains(weekday) {
                    continue
                }
            }
            
            // Update nearest alarm time
            if nearestAlarmTime == nil || alarmDate < nearestAlarmTime! {
                nearestAlarmTime = alarmDate
            }
        }
        
        return nearestAlarmTime
    }
    
    private func executeCurrentAlarms() {
        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentWeekday = calendar.component(.weekday, from: now)
        
        for alarm in alarms where alarm.isEnabled && alarm.autoExecute {
            guard let alarmHour = alarm.time.hour,
                  let alarmMinute = alarm.time.minute else {
                continue
            }
            
            if alarmHour == currentHour && alarmMinute == currentMinute {
                if alarm.daysOfWeek.isEmpty || alarm.daysOfWeek.contains(currentWeekday) {
                    print("⏰ Timer triggered alarm: \(alarm.formattedTime)")
                    executeAlarm(alarm)
                }
            }
        }
    }

    // MARK: - Migration
    
    private func migrateOldAlarms() {
        // Check if we already migrated
        if UserDefaults.standard.data(forKey: alarmsKey) != nil {
            return
        }
        
        // Try to load old ProfileAlarm data
        if let oldData = UserDefaults.standard.data(forKey: legacyAlarmsKey) {
            do {
                let decoder = JSONDecoder()
                let oldAlarms = try decoder.decode([LegacyProfileAlarm].self, from: oldData)
                
                // Convert to new Alarm format
                alarms = oldAlarms.map { old in
                    Alarm(
                        id: old.id,
                        time: old.time,
                        type: .profile,
                        targetID: old.targetProfileID,
                        isEnabled: old.isEnabled,
                        autoExecute: old.autoSwitch,
                        daysOfWeek: old.daysOfWeek
                    )
                }
                
                saveAlarms()
                
                // Remove old data
                UserDefaults.standard.removeObject(forKey: legacyAlarmsKey)
                print("✅ Migrated \(oldAlarms.count) profile alarms to new format")
            } catch {
                print("❌ Failed to migrate old alarms: \(error)")
            }
        }
    }

    // MARK: - Persistence

    private func loadAlarms() {
        if let data = UserDefaults.standard.data(forKey: alarmsKey),
            let decoded = try? JSONDecoder().decode([Alarm].self, from: data)
        {
            alarms = decoded
        }
    }

    private func saveAlarms() {
        if let encoded = try? JSONEncoder().encode(alarms) {
            UserDefaults.standard.set(encoded, forKey: alarmsKey)
        }
    }

    private func loadSnoozedAlarms() {
        if let data = UserDefaults.standard.data(forKey: snoozedAlarmsKey),
            let decoded = try? JSONDecoder().decode([SnoozedAlarm].self, from: data)
        {
            // Only keep non-expired snoozed alarms
            snoozedAlarms = decoded.filter { $0.snoozeUntil > Date() }
            if snoozedAlarms.count != decoded.count {
                saveSnoozedAlarms()  // Clean up expired ones
            }
        }
    }

    private func saveSnoozedAlarms() {
        if let encoded = try? JSONEncoder().encode(snoozedAlarms) {
            UserDefaults.standard.set(encoded, forKey: snoozedAlarmsKey)
        }
    }

    // MARK: - Alarm Management

    func addAlarm(_ alarm: Alarm) -> Bool {
        // Check for duplicate alarm at same time
        if alarms.contains(where: {
            $0.time.hour == alarm.time.hour && $0.time.minute == alarm.time.minute
                && $0.id != alarm.id
        }) {
            return false
        }
        alarms.append(alarm)
        saveAlarms()

        if alarm.isEnabled {
            scheduleAlarm(alarm)
        }
        
        // Reschedule timer for next alarm
        scheduleNextAlarmCheck()

        print("➕ Added \(alarm.type.rawValue) alarm: \(alarm.formattedTime) → \(alarm.daysOfWeekString)")
        return true
    }

    func updateAlarm(_ alarm: Alarm) {
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
            saveAlarms()

            // Remove old notification
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: ["alarm-\(alarm.id.uuidString)"])

            // Schedule new one if enabled
            if alarm.isEnabled {
                scheduleAlarm(alarm)
            }
            
            // Reschedule timer for next alarm
            scheduleNextAlarmCheck()

            print("✏️ Updated \(alarm.type.rawValue) alarm: \(alarm.formattedTime)")
        }
    }

    func deleteAlarm(_ alarm: Alarm) {
        alarms.removeAll(where: { $0.id == alarm.id })
        saveAlarms()

        // Remove from notification center
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["alarm-\(alarm.id.uuidString)"])
        
        // Reschedule timer for next alarm
        scheduleNextAlarmCheck()

        print("🗑️ Deleted \(alarm.type.rawValue) alarm: \(alarm.formattedTime)")
    }

    func toggleAlarm(_ alarm: Alarm) {
        var updatedAlarm = alarm
        updatedAlarm.isEnabled.toggle()
        updateAlarm(updatedAlarm)
    }

    // MARK: - Notification Scheduling

    func scheduleAlarm(_ alarm: Alarm) {
        guard alarm.isEnabled else { return }

        let targetName = alarm.getTargetName() ?? "Unknown"
        
        let content = UNMutableNotificationContent()
        
        // Set content based on alarm type
        switch alarm.type {
        case .profile:
            content.title = alarm.autoExecute ? "Profile Switched" : "Switch Profile?"
            content.body = alarm.autoExecute
                ? "Automatically switched to '\(targetName)'"
                : "Time to switch to '\(targetName)' profile"
            content.categoryIdentifier = alarm.autoExecute ? "PROFILE_SWITCH_AUTO" : "PROFILE_SWITCH"
            
            // Add user info for profile alarms
            content.userInfo = [
                "alarmID": "alarm-\(alarm.id.uuidString)",
                "profileID": alarm.targetID.uuidString,
                "profileName": targetName,
                "autoSwitch": alarm.autoExecute,
                "alarmType": AlarmType.profile.rawValue,
            ]
            
        case .template:
            content.title = alarm.autoExecute ? "Template Launched" : "Launch Template?"
            content.body = alarm.autoExecute
                ? "Automatically launched '\(targetName)' template"
                : "Time to launch '\(targetName)' template"
            content.categoryIdentifier = alarm.autoExecute ? "TEMPLATE_LAUNCH_AUTO" : "TEMPLATE_LAUNCH"
            
            // Add user info for template alarms
            content.userInfo = [
                "alarmID": "alarm-\(alarm.id.uuidString)",
                "templateID": alarm.targetID.uuidString,
                "templateName": targetName,
                "autoExecute": alarm.autoExecute,
                "alarmType": AlarmType.template.rawValue,
            ]
        }
        
        content.sound = .default
        
        // For auto-execute alarms, make them time-sensitive so the app wakes up
        if alarm.autoExecute {
            content.interruptionLevel = .timeSensitive
        }

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
                print("✅ Scheduled \(alarm.type.rawValue) alarm: \(alarm.formattedTime) for \(targetName)")
            }
        }
    }

    func rescheduleAllAlarms() {
        // Remove all pending notifications
        let identifiers = alarms.map { "alarm-\($0.id.uuidString)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: identifiers)

        // Reschedule enabled alarms
        for alarm in alarms where alarm.isEnabled {
            scheduleAlarm(alarm)
        }

        print("🔄 Rescheduled all alarms")
    }

    // MARK: - Alarm Execution
    
    func executeAlarm(_ alarm: Alarm) {
        switch alarm.type {
        case .profile:
            executeProfileAlarm(alarm)
        case .template:
            executeTemplateAlarm(alarm)
        }
    }
    
    private func executeProfileAlarm(_ alarm: Alarm) {
        ExcludedAppsManager.shared.selectedProfileID = alarm.targetID
        if let profileName = alarm.getTargetName() {
            print("✅ Auto-switched to profile: \(profileName)")
        }
    }
    
    private func executeTemplateAlarm(_ alarm: Alarm) {
        guard let template = AppTemplateManager.shared.templates.first(where: { $0.id == alarm.targetID }) else {
            print("❌ Template not found for alarm")
            return
        }
        AppTemplateManager.shared.launch(template: template)
        print("✅ Auto-launched template: \(template.name)")
    }

    // MARK: - Snooze Handling

    func scheduleSnoozeNotification(
        alarm: Alarm, minutes: Int
    ) {
        let snoozeID = "snooze-\(UUID().uuidString)"
        let snoozeUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let targetName = alarm.getTargetName() ?? "Unknown"

        let content = UNMutableNotificationContent()
        
        // Set content based on alarm type
        switch alarm.type {
        case .profile:
            content.title = "Profile Switch Reminder (Snoozed)"
            content.body = "Time to switch to '\(targetName)' profile"
            content.categoryIdentifier = "PROFILE_SWITCH"
            content.userInfo = [
                "alarmID": "alarm-\(alarm.id.uuidString)",
                "profileID": alarm.targetID.uuidString,
                "profileName": targetName,
                "autoSwitch": false,  // Never auto-execute snoozed alarms
                "alarmType": AlarmType.profile.rawValue,
            ]
            
        case .template:
            content.title = "Template Launch Reminder (Snoozed)"
            content.body = "Time to launch '\(targetName)' template"
            content.categoryIdentifier = "TEMPLATE_LAUNCH"
            content.userInfo = [
                "alarmID": "alarm-\(alarm.id.uuidString)",
                "templateID": alarm.targetID.uuidString,
                "templateName": targetName,
                "autoExecute": false,  // Never auto-execute snoozed alarms
                "alarmType": AlarmType.template.rawValue,
            ]
        }
        
        content.sound = .default

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
                print("⏰ Snoozed \(alarm.type.rawValue) alarm for \(minutes) minutes")
                DispatchQueue.main.async {
                    let snoozedAlarm = SnoozedAlarm(
                        id: snoozeID,
                        alarmID: "alarm-\(alarm.id.uuidString)",
                        type: alarm.type,
                        targetID: alarm.targetID.uuidString,
                        targetName: targetName,
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

        print("🗑️ Canceled snooze: \(snooze.targetName)")
    }
}

// MARK: - Legacy Model for Migration

private struct LegacyProfileAlarm: Codable {
    let id: UUID
    var time: DateComponents
    var targetProfileID: UUID
    var isEnabled: Bool
    var autoSwitch: Bool
    var daysOfWeek: Set<Int>
}
