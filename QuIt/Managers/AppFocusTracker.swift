//
//  AppFocusTracker.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import AppKit
import Combine
import Foundation

// Manager to track app focus times for auto-quit feature
class AppFocusTracker: ObservableObject {
    static let shared = AppFocusTracker()
    
    private let focusTimesKey = "appFocusTimes"
    private var focusTimes: [String: Date] = [:]
    private var workspaceObserver: NSObjectProtocol?
    
    private init() {
        loadFocusTimes()
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    private func loadFocusTimes() {
        if let data = UserDefaults.standard.data(forKey: focusTimesKey),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            focusTimes = decoded
        }
    }
    
    private func saveFocusTimes() {
        if let encoded = try? JSONEncoder().encode(focusTimes) {
            UserDefaults.standard.set(encoded, forKey: focusTimesKey)
        }
    }
    
    private func startMonitoring() {
        // Monitor app activation events
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            
            // Record focus time
            self.recordFocusTime(for: bundleID)
        }
        
        // Record current active app on start
        if let activeApp = NSWorkspace.shared.frontmostApplication,
           let bundleID = activeApp.bundleIdentifier {
            recordFocusTime(for: bundleID)
        }
    }
    
    private func stopMonitoring() {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
    }
    
    private func recordFocusTime(for bundleID: String) {
        let now = Date()
        focusTimes[bundleID] = now
        saveFocusTimes()
        
        print("📍 App focus recorded: \(bundleID) at \(now)")
    }
    
    // Public method for AutoQuitManager to initialize focus times
    func recordInitialFocusTime(for bundleID: String) {
        // Only record if not already tracked
        if focusTimes[bundleID] == nil {
            focusTimes[bundleID] = Date()
            saveFocusTimes()
        }
    }
    
    func getLastFocusTime(for bundleID: String?) -> Date? {
        guard let bundleID = bundleID else { return nil }
        return focusTimes[bundleID]
    }
    
    func getAllFocusTimes() -> [String: Date] {
        return focusTimes
    }
    
    func clearFocusTime(for bundleID: String) {
        focusTimes.removeValue(forKey: bundleID)
        saveFocusTimes()
    }
    
    func clearAllFocusTimes() {
        focusTimes.removeAll()
        saveFocusTimes()
    }
    
    func getTimeSinceLastFocus(for bundleID: String?) -> TimeInterval? {
        guard let lastFocus = getLastFocusTime(for: bundleID) else { return nil }
        return Date().timeIntervalSince(lastFocus)
    }
}

