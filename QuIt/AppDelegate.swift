import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure popover with SwiftUI content
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 320, height: 220) // Outer size; SwiftUI view has its own width
        popover.contentViewController = NSHostingController(
            rootView: ContentView()
                .ignoresSafeArea() // Allow material to reach edges
        )
        popover.delegate = self

        // Create status item with an image template
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Use a system symbol that looks good in the menu bar
            let image = NSImage(systemSymbolName: "power", accessibilityDescription: "QuIt")
            image?.isTemplate = true // Adapts to light/dark menu bar
            button.image = image
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
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
        }
    }
    
    // NSPopoverDelegate method - called when popover is about to show
    func popoverWillShow(_ notification: Notification) {
        // Post notification to reload apps list
        NotificationCenter.default.post(name: .popoverWillOpen, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup if needed
    }
}
