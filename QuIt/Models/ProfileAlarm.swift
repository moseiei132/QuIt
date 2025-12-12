//
//  ProfileAlarm.swift
//  QuIt
//
//  Created by Antigravity on 12/12/2568 BE.
//

import Foundation

struct ProfileAlarm: Codable, Identifiable, Hashable {
    let id: UUID
    var time: DateComponents  // hour, minute (e.g., 9:00 AM = hour: 9, minute: 0)
    var targetProfileID: UUID
    var isEnabled: Bool
    var autoSwitch: Bool  // true = auto-switch, false = alert only
    var daysOfWeek: Set<Int>  // 1=Sunday, 2=Monday, ..., 7=Saturday. Empty = every day

    init(
        id: UUID = UUID(),
        time: DateComponents,
        targetProfileID: UUID,
        isEnabled: Bool = true,
        autoSwitch: Bool = true,
        daysOfWeek: Set<Int> = []
    ) {
        self.id = id
        self.time = time
        self.targetProfileID = targetProfileID
        self.isEnabled = isEnabled
        self.autoSwitch = autoSwitch
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
}
