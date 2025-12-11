//
//  AppTemplate.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import Foundation

struct AppTemplate: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var items: [TemplateItem]
    
    // QuIt Tabs Integration
    var quitTabsEnabled: Bool = false
    var quitTabsColor: String = "random"  // "random" or specific color from VALID_COLORS
    var quitTabsGroup: String?  // nil defaults to template name
}

struct TemplateItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var bundleIdentifier: String
    var appName: String
    // We don't store the icon directly to keep the JSON small.
    // We'll look it up using the bundleIdentifier.

    // Universal parameters for app-specific configuration
    // Examples:
    // - Browsers: ["url": "https://google.com"]
    // - IDEs: ["path": "/path/to/project"]
    // - Terminal: ["command": "npm start"]
    var parameters: [String: String]?
}
