//
//  RunningApp.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import AppKit
import Foundation

// Model to represent a running app snapshot
struct RunningApp: Identifiable, Hashable {
    // Use pid for uniqueness to avoid duplicate IDs in LazyVStack.
    let id: Int
    let bundleIdentifier: String?
    let name: String
    let icon: NSImage?
    let isActive: Bool
    let pid: pid_t
    let lastFocusTime: Date?
}

