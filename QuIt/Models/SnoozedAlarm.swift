//
//  SnoozedAlarm.swift
//  QuIt
//
//  Created by Antigravity on 04/01/2569 BE.
//

import Foundation

struct SnoozedAlarm: Codable, Identifiable {
    let id: String  // Notification identifier
    let alarmID: String
    let type: AlarmType
    let targetID: String
    let targetName: String
    let snoozeUntil: Date
    let snoozeDuration: Int  // minutes
}
