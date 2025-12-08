//
//  KeepAwakeManager.swift
//  QuIt
//
//  Created by Dulyawat on 8/12/2568 BE.
//

import Combine
import Foundation
import IOKit.pwr_mgt

/// Manager for preventing Mac from sleeping while QuIt is running
class KeepAwakeManager: ObservableObject {
    static let shared = KeepAwakeManager()

    @Published var isEnabled: Bool = false {
        didSet {
            if !isLoading {
                saveSettings()
                if isEnabled {
                    enableKeepAwake()
                } else {
                    disableKeepAwake()
                }
            }
        }
    }

    private let isEnabledKey = "keepAwakeEnabled"
    private var assertionID: IOPMAssertionID = 0
    private var isLoading = false

    private init() {
        loadSettings()

        // Enable keep awake if it was previously enabled
        if isEnabled {
            enableKeepAwake()
        }

        print("✅ KeepAwakeManager initialized successfully")
    }

    deinit {
        // Always release assertion when manager is deallocated
        disableKeepAwake()
    }

    private func loadSettings() {
        isLoading = true
        isEnabled = UserDefaults.standard.bool(forKey: isEnabledKey)
        isLoading = false

        print("✅ Keep awake setting loaded: \(isEnabled)")
    }

    private func saveSettings() {
        UserDefaults.standard.set(isEnabled, forKey: isEnabledKey)
        UserDefaults.standard.synchronize()

        print("💾 Keep awake setting saved: \(isEnabled)")
    }

    private func enableKeepAwake() {
        // First, disable any existing assertion
        disableKeepAwake()

        // Create a new power assertion to prevent system sleep
        let reason = "QuIt - Keep Awake" as CFString

        // Use NoIdleSleep to prevent both display and system sleep
        let assertionType = kIOPMAssertionTypeNoIdleSleep as CFString

        let result = IOPMAssertionCreateWithName(
            assertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )

        if result == kIOReturnSuccess {
            print("✅ Keep awake enabled - assertion ID: \(assertionID)")
        } else {
            print("❌ Failed to enable keep awake - error code: \(result)")
        }
    }

    private func disableKeepAwake() {
        // Only release if we have a valid assertion
        guard assertionID != 0 else { return }

        let result = IOPMAssertionRelease(assertionID)

        if result == kIOReturnSuccess {
            print("✅ Keep awake disabled - assertion released: \(assertionID)")
            assertionID = 0
        } else {
            print("❌ Failed to release keep awake assertion - error code: \(result)")
        }
    }
}
