//
//  NotificationNames.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import Foundation

// Notification names for app state changes and events
extension Notification.Name {
    static let excludedAppsDidChange = Notification.Name("excludedAppsDidChange")
    static let popoverWillOpen = Notification.Name("popoverWillOpen")
    static let autoQuitSettingsDidChange = Notification.Name("autoQuitSettingsDidChange")
}

