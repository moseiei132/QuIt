//
//  AlarmType.swift
//  QuIt
//
//  Created by Antigravity on 04/01/2569 BE.
//

import Foundation

enum AlarmType: String, Codable {
    case profile
    case template
    
    var displayName: String {
        switch self {
        case .profile:
            return "Profile Switch"
        case .template:
            return "Template Launch"
        }
    }
    
    var icon: String {
        switch self {
        case .profile:
            return "person.crop.circle"
        case .template:
            return "list.bullet.rectangle"
        }
    }
}
