import Cocoa
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate,
    UNUserNotificationCenterDelegate
{
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var alarmNotificationWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure popover with SwiftUI content
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 320, height: 220)  // Outer size; SwiftUI view has its own width
        popover.contentViewController = NSHostingController(
            rootView: ContentView()
                .ignoresSafeArea()  // Allow material to reach edges
        )
        popover.delegate = self

        // Create status item with an image template
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Use a system symbol that looks good in the menu bar
            let image = NSImage(systemSymbolName: "power", accessibilityDescription: "QuIt")
            image?.isTemplate = true  // Adapts to light/dark menu bar
            button.image = image
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // Setup notification center
        setupNotifications()

        // Initialize alarm manager and reschedule all alarms
        _ = ProfileAlarmManager.shared
        ProfileAlarmManager.shared.rescheduleAllAlarms()

        // Check for updates after launch (with delay to not slow down startup)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            UpdateChecker.shared.performAutoCheckIfNeeded()
        }
    }

    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Request permission
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("✅ Notification permission granted")
            } else if let error = error {
                print("❌ Notification permission error: \(error.localizedDescription)")
            }
        }

        // Register notification categories
        let switchAction = UNNotificationAction(
            identifier: "SWITCH_PROFILE",
            title: "Switch Profile",
            options: [.foreground]
        )

        let rejectAction = UNNotificationAction(
            identifier: "REJECT_SWITCH",
            title: "Reject"
        )

        // Snooze button - no foreground option, snoozes immediately using settings duration
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_ALARM",
            title: "Snooze"
        )

        let category = UNNotificationCategory(
            identifier: "PROFILE_SWITCH",
            actions: [switchAction, rejectAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([category])
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Position the popover under the status item
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Ensure the app becomes active so keyboard focus works
            NSApp.activate(ignoringOtherApps: true)
            // Make the popover window the key window to receive focus
            // Use a small delay to ensure the window is fully initialized
            DispatchQueue.main.async {
                self.popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    // NSPopoverDelegate method - called when popover is about to show
    func popoverWillShow(_ notification: Notification) {
        // Post notification to reload apps list
        NotificationCenter.default.post(name: .popoverWillOpen, object: nil)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Check if this is an alarm notification
        let userInfo = notification.request.content.userInfo

        if let profileIDStr = userInfo["profileID"] as? String,
            let profileID = UUID(uuidString: profileIDStr),
            let autoSwitch = userInfo["autoSwitch"] as? Bool
        {

            // Skip notification if current profile already matches target
            if ExcludedAppsManager.shared.selectedProfileID == profileID {
                print("⏭️ Skipping notification - already on target profile")
                return []  // Don't show notification
            }

            // If auto-switch mode, switch profile immediately
            if autoSwitch {
                await MainActor.run {
                    ExcludedAppsManager.shared.selectedProfileID = profileID
                    if let profileName = userInfo["profileName"] as? String {
                        print("✅ Auto-switched to profile: \(profileName)")
                    }
                }
                return []  // Don't show notification after auto-switch
            }
        }

        // Show notification for alert mode
        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let alarmID = userInfo["alarmID"] as? String ?? ""
        let profileIDStr = userInfo["profileID"] as? String ?? ""
        let profileName = userInfo["profileName"] as? String ?? "Unknown"

        print("📱 Received notification action: \(response.actionIdentifier)")

        switch response.actionIdentifier {
        case "SWITCH_PROFILE":
            // Switch to target profile immediately
            if let profileID = UUID(uuidString: profileIDStr) {
                await MainActor.run {
                    ExcludedAppsManager.shared.selectedProfileID = profileID
                    print("✅ Switched to profile: \(profileName)")

                    // Send confirmation notification
                    sendConfirmationNotification(profileName: profileName)
                }
            }

        case "REJECT_SWITCH":
            // User rejected the switch, do nothing
            print("❌ Profile switch rejected")

        case "SNOOZE_ALARM":
            // Show snooze modal to select duration
            await MainActor.run {
                showAlarmNotificationWindow(
                    profileID: profileIDStr, profileName: profileName, alarmID: alarmID)
            }

        case UNNotificationDefaultActionIdentifier:
            // User clicked notification body - show mini window
            await MainActor.run {
                showAlarmNotificationWindow(
                    profileID: profileIDStr, profileName: profileName, alarmID: alarmID)
            }

        default:
            // Don't handle unknown actions
            break
        }
    }

    private func showAlarmNotificationWindow(
        profileID: String, profileName: String, alarmID: String
    ) {
        // Close existing window if any
        alarmNotificationWindow?.close()

        let notificationView = AlarmNotificationView(
            profileName: profileName,
            onSwitch: {
                // Switch profile
                if let profileUUID = UUID(uuidString: profileID) {
                    ExcludedAppsManager.shared.selectedProfileID = profileUUID
                    print("✅ Switched to profile: \(profileName)")

                    // Send confirmation notification
                    self.sendConfirmationNotification(profileName: profileName)
                }
                self.alarmNotificationWindow?.close()
                self.alarmNotificationWindow = nil
            },
            onReject: {
                // Just close
                print("❌ Profile switch rejected")
                self.alarmNotificationWindow?.close()
                self.alarmNotificationWindow = nil
            },
            onSnooze: { minutes in
                // Snooze for selected duration
                ProfileAlarmManager.shared.scheduleSnoozeNotification(
                    alarmID: alarmID,
                    profileID: profileID,
                    profileName: profileName,
                    minutes: minutes
                )

                print("⏰ Snoozed for \(minutes) minutes")
                self.alarmNotificationWindow?.close()
                self.alarmNotificationWindow = nil
            }
        )

        let hostingController = NSHostingController(rootView: notificationView)

        // Create borderless window
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.borderless, .fullSizeContentView]
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .floating
        window.hasShadow = true

        // Position at center of screen
        window.center()

        // Show window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        alarmNotificationWindow = window
    }

    private func sendConfirmationNotification(profileName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Profile Switched"
        content.body = "Now using '\(profileName)' profile"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "profile-switched-\(UUID().uuidString)",
            content: content,
            trigger: nil  // Show immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send confirmation: \(error.localizedDescription)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup if needed
        NotificationCenter.default.removeObserver(self)
    }
}
