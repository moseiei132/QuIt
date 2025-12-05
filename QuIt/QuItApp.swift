//
//  QuItApp.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import SwiftUI

@main
struct QuItApp: App {
    // Hook into AppDelegate to manage NSStatusItem / NSPopover lifecycle
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window. Keep an empty Settings scene if you want app preferences later.
        Settings {
            EmptyView()
        }
    }
}
