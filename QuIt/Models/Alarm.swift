//
//  Alarm.swift
//  QuIt
//
//  Created by Antigravity on 04/01/2569 BE.
//

import Foundation

struct Alarm: Codable, Identifiable, Hashable {
    let id: UUID
    var time: DateComponents  // hour, minute (e.g., 9:00 AM = hour: 9, minute: 0)
    var type: AlarmType
    var targetID: UUID  // Profile ID or Template ID
    var isEnabled: Bool
    var autoExecute: Bool  // true = auto-run, false = notification only
    var daysOfWeek: Set<Int>  // 1=Sunday, 2=Monday, ..., 7=Saturday. Empty = every day

    init(
        id: UUID = UUID(),
        time: DateComponents,
        type: AlarmType,
        targetID: UUID,
        isEnabled: Bool = true,
        autoExecute: Bool = true,
        daysOfWeek: Set<Int> = []
    ) {
        self.id = id
        self.time = time
        self.type = type
        self.targetID = targetID
        self.isEnabled = isEnabled
        self.autoExecute = autoExecute
        self.daysOfWeek = daysOfWeek
    }

    var formattedTime: String {
        let calendar = Calendar.current
        var dateComponents = DateComponents()
        dateComponents.hour = time.hour
        dateComponents.minute = time.minute

        guard let date = calendar.date(from: dateComponents) else {
            return "Invalid time"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    var daysOfWeekString: String {
        if daysOfWeek.isEmpty {
            return "Every day"
        } else if daysOfWeek.count == 7 {
            return "Every day"
        } else if daysOfWeek.count == 5 && !daysOfWeek.contains(1) && !daysOfWeek.contains(7) {
            return "Weekdays"  // Mon-Fri
        } else if daysOfWeek.count == 2 && daysOfWeek.contains(1) && daysOfWeek.contains(7) {
            return "Weekends"  // Sat-Sun
        } else {
            // Show abbreviated days: "Mon, Wed, Fri"
            let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            return daysOfWeek.sorted().map { dayNumber in
                dayNames[dayNumber - 1]
            }.joined(separator: ", ")
        }
    }

    func shouldTriggerToday() -> Bool {
        if daysOfWeek.isEmpty {
            return true  // Every day
        }

        let calendar = Calendar.current
        let today = calendar.component(.weekday, from: Date())
        return daysOfWeek.contains(today)
    }
    
    // Helper to get target name based on type
    func getTargetName() -> String? {
        switch type {
        case .profile:
            return ExcludedAppsManager.shared.profiles.first(where: { $0.id == targetID })?.name
        case .template:
            return AppTemplateManager.shared.templates.first(where: { $0.id == targetID })?.name
        }
    }
}
