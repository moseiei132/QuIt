//
//  AppTemplateManager.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import AppKit
import Combine
import Foundation

class AppTemplateManager: ObservableObject {
    static let shared = AppTemplateManager()

    @Published var templates: [AppTemplate] = []
    @Published var selectedTemplateID: UUID?

    private let inputsKey = "savedAppTemplates"

    private init() {
        loadTemplates()
    }

    func loadTemplates() {
        if let data = UserDefaults.standard.data(forKey: inputsKey) {
            if let decoded = try? JSONDecoder().decode([AppTemplate].self, from: data) {
                templates = decoded
                return
            }
        }
        templates = []
    }

    func saveTemplates() {
        if let encoded = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(encoded, forKey: inputsKey)
        }
    }

    func addTemplate(_ template: AppTemplate) {
        templates.append(template)
        saveTemplates()
    }

    func updateTemplate(_ template: AppTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
            saveTemplates()
        }
    }

    func deleteTemplate(at index: Int) {
        templates.remove(at: index)
        saveTemplates()
    }

    func deleteTemplate(id: UUID) {
        templates.removeAll(where: { $0.id == id })

        // Update selection if needed
        if selectedTemplateID == id {
            selectedTemplateID = templates.first?.id
        }

        saveTemplates()
    }

    func duplicateTemplate(_ template: AppTemplate) {
        var newTemplate = template
        newTemplate.id = UUID()
        newTemplate.name = "\(template.name) Copy"
        templates.append(newTemplate)
        selectedTemplateID = newTemplate.id
        saveTemplates()
    }

    func renameTemplate(_ template: AppTemplate, to newName: String) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index].name = newName
            saveTemplates()
        }
    }

    // MARK: - Launching Logic

    func launch(template: AppTemplate) {
        for item in template.items {
            launchItem(item)
        }
    }

    private func launchItem(_ item: TemplateItem) {
        // Check if there are any parameters
        guard let params = item.parameters, !params.isEmpty else {
            // No parameters - just launch the app normally
            launchApp(bundleId: item.bundleIdentifier, appName: item.appName)
            return
        }

        // Handle URL parameters (for browsers) - support multiple URLs
        let urlParams = params.filter { $0.key.starts(with: "url") }
        if !urlParams.isEmpty {
            let urls = urlParams.sorted(by: { $0.key < $1.key })
                .compactMap { URL(string: $0.value) }
                .filter { !$0.absoluteString.isEmpty }

            if !urls.isEmpty {
                if let appURL = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: item.bundleIdentifier)
                {
                    let configuration = NSWorkspace.OpenConfiguration()

                    NSWorkspace.shared.open(
                        urls, withApplicationAt: appURL, configuration: configuration
                    ) { application, error in
                        if let error = error {
                            print(
                                "Error opening URLs with \(item.appName): \(error.localizedDescription)"
                            )
                            // Fallback: open URLs with default browser
                            urls.forEach { NSWorkspace.shared.open($0) }
                        }
                    }
                } else {
                    print(
                        "Could not find app for bundle ID: \(item.bundleIdentifier). Opening URLs with default browser."
                    )
                    urls.forEach { NSWorkspace.shared.open($0) }
                }
                return
            }
        }

        // Handle path parameters (for IDEs/editors) - support multiple paths
        let pathParams = params.filter { $0.key.starts(with: "path") }
        if !pathParams.isEmpty {
            let paths = pathParams.sorted(by: { $0.key < $1.key })
                .map { URL(fileURLWithPath: $0.value) }
                .filter { !$0.path.isEmpty }

            if !paths.isEmpty {
                if let appURL = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: item.bundleIdentifier)
                {
                    let configuration = NSWorkspace.OpenConfiguration()

                    NSWorkspace.shared.open(
                        paths, withApplicationAt: appURL, configuration: configuration
                    ) { application, error in
                        if let error = error {
                            print(
                                "Error opening paths with \(item.appName): \(error.localizedDescription)"
                            )
                        }
                    }
                } else {
                    print("Could not find app for bundle ID: \(item.bundleIdentifier)")
                }
                return
            }
        }

        // Default: just launch the app
        launchApp(bundleId: item.bundleIdentifier, appName: item.appName)
    }

    private func launchApp(bundleId: String, appName: String) {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true

            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) {
                application, error in
                if let error = error {
                    print("Error launching \(appName): \(error.localizedDescription)")
                }
            }
        } else {
            print("Could not find app for bundle ID: \(bundleId)")
        }
    }
}
