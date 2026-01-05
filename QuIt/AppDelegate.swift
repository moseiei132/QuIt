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
        _ = AlarmManager.shared
        AlarmManager.shared.rescheduleAllAlarms()

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
        
        let launchAction = UNNotificationAction(
            identifier: "LAUNCH_TEMPLATE",
            title: "Launch Template",
            options: [.foreground]
        )

        let rejectAction = UNNotificationAction(
            identifier: "REJECT_ACTION",
            title: "Reject"
        )

        // Snooze button - no foreground option, snoozes immediately using settings duration
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_ALARM",
            title: "Snooze"
        )

        let profileCategory = UNNotificationCategory(
            identifier: "PROFILE_SWITCH",
            actions: [switchAction, rejectAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )
        
        let templateCategory = UNNotificationCategory(
            identifier: "TEMPLATE_LAUNCH",
            actions: [launchAction, rejectAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )

        // Auto categories - no actions, just informational
        let autoSwitchCategory = UNNotificationCategory(
            identifier: "PROFILE_SWITCH_AUTO",
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        
        let autoLaunchCategory = UNNotificationCategory(
            identifier: "TEMPLATE_LAUNCH_AUTO",
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([profileCategory, templateCategory, autoSwitchCategory, autoLaunchCategory])
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

    // NSPopoverDelegate method - called to determine if popover should close
    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        // Allow popover to close when it loses focus
        return true
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Check if this is an alarm notification
        let userInfo = notification.request.content.userInfo
        let alarmTypeStr = userInfo["alarmType"] as? String
        let autoExecute = userInfo["autoSwitch"] as? Bool ?? userInfo["autoExecute"] as? Bool ?? false
        
        print("🔔 willPresent called - Type: \(alarmTypeStr ?? "unknown"), AutoExecute: \(autoExecute)")
        
        // Handle profile alarm
        if alarmTypeStr == "profile",
           let profileIDStr = userInfo["profileID"] as? String,
           let profileID = UUID(uuidString: profileIDStr)
        {
            // Skip notification if current profile already matches target
            if ExcludedAppsManager.shared.selectedProfileID == profileID {
                print("⏭️ Skipping notification - already on target profile")
                return []  // Don't show notification
            }

            // If auto-execute mode, switch profile immediately
            if autoExecute {
                await MainActor.run {
                    ExcludedAppsManager.shared.selectedProfileID = profileID
                    if let profileName = userInfo["profileName"] as? String {
                        print("✅ Auto-switched to profile: \(profileName)")
                    }
                }
                return []  // Don't show notification after auto-switch
            }
        }
        
        // Handle template alarm
        if alarmTypeStr == "template",
           let templateIDStr = userInfo["templateID"] as? String,
           let templateID = UUID(uuidString: templateIDStr)
        {
            print("🎯 Template alarm detected - ID: \(templateID)")
            
            // If auto-execute mode, launch template immediately
            if autoExecute {
                print("🚀 Attempting to auto-launch template...")
                await MainActor.run {
                    if let template = AppTemplateManager.shared.templates.first(where: { $0.id == templateID }) {
                        print("✅ Found template: \(template.name)")
                        AppTemplateManager.shared.launch(template: template)
                        if let templateName = userInfo["templateName"] as? String {
                            print("✅ Auto-launched template: \(templateName)")
                        }
                    } else {
                        print("❌ Template not found!")
                    }
                }
                return []  // Don't show notification after auto-launch
            }
        }

        // Show notification for alert mode
        print("📢 Showing notification banner")
        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let alarmID = userInfo["alarmID"] as? String ?? ""
        let alarmTypeStr = userInfo["alarmType"] as? String
        let autoExecute = userInfo["autoSwitch"] as? Bool ?? userInfo["autoExecute"] as? Bool ?? false
        
        // Profile alarm info
        let profileIDStr = userInfo["profileID"] as? String ?? ""
        let profileName = userInfo["profileName"] as? String ?? "Unknown"
        
        // Template alarm info
        let templateIDStr = userInfo["templateID"] as? String ?? ""
        let templateName = userInfo["templateName"] as? String ?? "Unknown"

        print("📱 Received notification action: \(response.actionIdentifier)")

        // Handle default action (user clicked on notification banner or dismissed it)
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            // For auto-execute alarms, execute immediately
            if autoExecute {
                if alarmTypeStr == "profile", let profileID = UUID(uuidString: profileIDStr) {
                    if ExcludedAppsManager.shared.selectedProfileID != profileID {
                        await MainActor.run {
                            ExcludedAppsManager.shared.selectedProfileID = profileID
                            print("✅ Auto-switched to profile: \(profileName)")
                            sendProfileConfirmationNotification(profileName: profileName)
                        }
                    }
                } else if alarmTypeStr == "template", let templateID = UUID(uuidString: templateIDStr) {
                    await MainActor.run {
                        if let template = AppTemplateManager.shared.templates.first(where: { $0.id == templateID }) {
                            AppTemplateManager.shared.launch(template: template)
                            print("✅ Auto-launched template: \(templateName)")
                            sendTemplateConfirmationNotification(templateName: templateName)
                        }
                    }
                }
                return
            }
            
            // For non-auto alarms, show the notification window
            await MainActor.run {
                showAlarmNotificationWindow(
                    alarmID: alarmID,
                    alarmType: alarmTypeStr ?? "profile",
                    targetID: alarmTypeStr == "template" ? templateIDStr : profileIDStr,
                    targetName: alarmTypeStr == "template" ? templateName : profileName
                )
            }
            return
        }

        switch response.actionIdentifier {
        case "SWITCH_PROFILE":
            // Switch to target profile immediately
            if let profileID = UUID(uuidString: profileIDStr) {
                await MainActor.run {
                    ExcludedAppsManager.shared.selectedProfileID = profileID
                    print("✅ Switched to profile: \(profileName)")
                    sendProfileConfirmationNotification(profileName: profileName)
                }
            }
            
        case "LAUNCH_TEMPLATE":
            // Launch template immediately
            if let templateID = UUID(uuidString: templateIDStr),
               let template = AppTemplateManager.shared.templates.first(where: { $0.id == templateID }) {
                await MainActor.run {
                    AppTemplateManager.shared.launch(template: template)
                    print("✅ Launched template: \(templateName)")
                    sendTemplateConfirmationNotification(templateName: templateName)
                }
            }

        case "REJECT_ACTION":
            // User rejected the action, do nothing
            print("❌ Alarm action rejected")

        case "SNOOZE_ALARM":
            // Show snooze modal to select duration
            await MainActor.run {
                showAlarmNotificationWindow(
                    alarmID: alarmID,
                    alarmType: alarmTypeStr ?? "profile",
                    targetID: alarmTypeStr == "template" ? templateIDStr : profileIDStr,
                    targetName: alarmTypeStr == "template" ? templateName : profileName
                )
            }

        default:
            // Don't handle unknown actions
            break
        }
    }

    private func showAlarmNotificationWindow(
        alarmID: String, alarmType: String, targetID: String, targetName: String
    ) {
        // Close existing window if any
        alarmNotificationWindow?.close()
        
        let isProfile = alarmType == "profile"

        let notificationView = AlarmNotificationView(
            targetName: targetName,
            isProfile: isProfile,
            onExecute: {
                if isProfile {
                    // Switch profile
                    if let profileUUID = UUID(uuidString: targetID) {
                        ExcludedAppsManager.shared.selectedProfileID = profileUUID
                        print("✅ Switched to profile: \(targetName)")
                        self.sendProfileConfirmationNotification(profileName: targetName)
                    }
                } else {
                    // Launch template
                    if let templateUUID = UUID(uuidString: targetID),
                       let template = AppTemplateManager.shared.templates.first(where: { $0.id == templateUUID }) {
                        AppTemplateManager.shared.launch(template: template)
                        print("✅ Launched template: \(targetName)")
                        self.sendTemplateConfirmationNotification(templateName: targetName)
                    }
                }
                self.alarmNotificationWindow?.close()
                self.alarmNotificationWindow = nil
            },
            onReject: {
                print("❌ Alarm action rejected")
                self.alarmNotificationWindow?.close()
                self.alarmNotificationWindow = nil
            },
            onSnooze: { minutes in
                // Find the alarm and snooze it
                if let alarm = AlarmManager.shared.alarms.first(where: { "alarm-\($0.id.uuidString)" == alarmID }) {
                    AlarmManager.shared.scheduleSnoozeNotification(
                        alarm: alarm,
                        minutes: minutes
                    )
                    print("⏰ Snoozed for \(minutes) minutes")
                }
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

    private func sendProfileConfirmationNotification(profileName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Profile Switched"
        content.body = "Now using '\(profileName)' profile"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "profile-switched-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send confirmation: \(error.localizedDescription)")
            }
        }
    }
    
    private func sendTemplateConfirmationNotification(templateName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Template Launched"
        content.body = "Launched '\(templateName)' template"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "template-launched-\(UUID().uuidString)",
            content: content,
            trigger: nil
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
