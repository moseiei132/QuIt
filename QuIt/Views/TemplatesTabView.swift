//
//  TemplatesTabView.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TemplatesTabView: View {
    @StateObject private var manager = AppTemplateManager.shared
    @State private var showingNewTemplateSheet = false
    @State private var newTemplateName = ""
    @State private var showingRenameSheet = false
    @State private var templateToRename: AppTemplate?
    @State private var renameTemplateName = ""
    @State private var showingAddAppSheet = false
    @State private var editingItemId: UUID?
    @StateObject private var runningAppsModel = RunningAppsModel()
    @FocusState private var focusedField: String?

    var currentTemplate: AppTemplate? {
        if let selectedId = manager.selectedTemplateID {
            return manager.templates.first(where: { $0.id == selectedId })
        }
        return manager.templates.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create templates to quickly launch sets of applications with custom parameters.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            // Template selector and management
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Template:")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Picker(
                        "",
                        selection: Binding(
                            get: {
                                manager.selectedTemplateID ?? manager.templates.first?.id ?? UUID()
                            },
                            set: { manager.selectedTemplateID = $0 }
                        )
                    ) {
                        ForEach(manager.templates) { template in
                            Text(template.name).tag(template.id)
                        }
                    }
                    .frame(maxWidth: 200)

                    Spacer()

                    // Template management buttons
                    Menu {
                        Button {
                            showingNewTemplateSheet = true
                        } label: {
                            Label("New Template", systemImage: "plus")
                        }

                        if let current = currentTemplate {
                            Button {
                                manager.duplicateTemplate(current)
                            } label: {
                                Label("Duplicate Template", systemImage: "doc.on.doc")
                            }

                            Button {
                                templateToRename = current
                                renameTemplateName = current.name
                                showingRenameSheet = true
                            } label: {
                                Label("Rename Template", systemImage: "pencil")
                            }

                            Divider()

                            Button(role: .destructive) {
                                manager.deleteTemplate(id: current.id)
                            } label: {
                                Label("Delete Template", systemImage: "trash")
                            }
                            .disabled(manager.templates.count <= 1)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Template Options")
                }
            }

            Divider()

            // List of apps in template
            if currentTemplate?.items.isEmpty ?? true {
                VStack(spacing: 12) {
                    Text("No applications in this template")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text("Click the + button below to add applications")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(currentTemplate?.items ?? []) { item in
                            appItemRow(item: item, isEditing: editingItemId == item.id)
                        }
                    }
                }
                .frame(maxHeight: 450)
            }

            Divider()

            // Add button
            HStack {
                Button {
                    runningAppsModel.reload()
                    showingAddAppSheet = true
                } label: {
                    Label("Add Application", systemImage: "plus.circle.fill")
                        .font(.body)
                }
                .buttonStyle(.borderedProminent)
                .help("Add an application to this template")

                Spacer()
            }

            Spacer()
        }
        .padding(20)
        .contentShape(Rectangle())
        .onTapGesture {
            // Dismiss focus when clicking outside TextFields
            focusedField = nil
        }
        .sheet(isPresented: $showingNewTemplateSheet) {
            VStack(spacing: 16) {
                Text("New Template")
                    .font(.headline)

                TextField("Template Name", text: $newTemplateName)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Cancel") {
                        showingNewTemplateSheet = false
                        newTemplateName = ""
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Create") {
                        if !newTemplateName.isEmpty {
                            let newTemplate = AppTemplate(name: newTemplateName, items: [])
                            manager.addTemplate(newTemplate)
                            manager.selectedTemplateID = newTemplate.id
                            showingNewTemplateSheet = false
                            newTemplateName = ""
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newTemplateName.isEmpty)
                }
            }
            .padding(20)
            .frame(width: 300)
        }
        .sheet(isPresented: $showingRenameSheet) {
            VStack(spacing: 16) {
                Text("Rename Template")
                    .font(.headline)

                TextField("Template Name", text: $renameTemplateName)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Cancel") {
                        showingRenameSheet = false
                        renameTemplateName = ""
                        templateToRename = nil
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Rename") {
                        if !renameTemplateName.isEmpty, let template = templateToRename {
                            manager.renameTemplate(template, to: renameTemplateName)
                            showingRenameSheet = false
                            renameTemplateName = ""
                            templateToRename = nil
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(renameTemplateName.isEmpty)
                }
            }
            .padding(20)
            .frame(width: 300)
        }
        .sheet(isPresented: $showingAddAppSheet) {
            AddAppSheet(showingSheet: $showingAddAppSheet, runningAppsModel: runningAppsModel) {
                app in
                guard let bundleId = app.bundleIdentifier else { return }
                let item = TemplateItem(
                    bundleIdentifier: bundleId, appName: app.name, parameters: nil)

                if let index = manager.templates.firstIndex(where: { $0.id == currentTemplate?.id })
                {
                    manager.templates[index].items.append(item)
                    manager.saveTemplates()

                    // Auto-open parameter editor for certain app types
                    if shouldShowParameterEditor(bundleId: bundleId) {
                        editingItemId = item.id
                    }
                }
            }
        }
    }

    // MARK: - App Item Row

    private func appItemRow(item: TemplateItem, isEditing: Bool) -> some View {
        VStack(spacing: 0) {
            // Main row
            HStack(spacing: 12) {
                // App icon
                if let icon = getIcon(for: item.bundleIdentifier) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)
                } else {
                    Image(systemName: "app")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }

                // App info
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.appName)
                        .font(.body)
                        .fontWeight(.medium)

                    if let params = item.parameters, !params.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "gearshape.fill")
                                .font(.caption2)
                                .foregroundStyle(.blue)

                            Text(formatParameters(params))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Text("No parameters")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                // Edit button
                Button {
                    withAnimation {
                        editingItemId = isEditing ? nil : item.id
                    }
                } label: {
                    Image(systemName: isEditing ? "chevron.up.circle.fill" : "pencil.circle")
                        .font(.title3)
                        .foregroundStyle(isEditing ? .green : .blue)
                }
                .buttonStyle(.plain)
                .help(isEditing ? "Collapse" : "Edit parameters")

                // Delete button
                Button(role: .destructive) {
                    if let index = manager.templates.firstIndex(where: {
                        $0.id == currentTemplate?.id
                    }),
                        let itemIndex = manager.templates[index].items.firstIndex(where: {
                            $0.id == item.id
                        })
                    {
                        manager.templates[index].items.remove(at: itemIndex)
                        manager.saveTemplates()
                        editingItemId = nil
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Remove from template")
            }

            // Inline parameter editor (expands within same box)
            if isEditing {
                Divider()
                    .padding(.vertical, 8)

                parameterEditorView(item: item)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(8)
    }

    private func parameterEditorView(item: TemplateItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if isBrowser(item.bundleIdentifier) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("URLs")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            addURL(to: item)
                        } label: {
                            Label("Add URL", systemImage: "plus.circle.fill")
                                .labelStyle(.iconOnly)
                                .font(.callout)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }

                    let urls = getURLs(from: item)

                    if urls.isEmpty {
                        Text("Click + to add URLs")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(0..<urls.count, id: \.self) { index in
                            HStack(spacing: 8) {
                                TextField(
                                    "https://example.com",
                                    text: Binding(
                                        get: {
                                            let currentURLs = getURLs(from: item)
                                            return index < currentURLs.count
                                                ? currentURLs[index] : ""
                                        },
                                        set: { newValue in
                                            updateURL(at: index, with: newValue, for: item)
                                        }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: "url-\(item.id)-\(index)")

                                Button {
                                    removeURL(at: index, from: item)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            if isIDE(item.bundleIdentifier) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Project Paths")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            addPath(to: item)
                        } label: {
                            Label("Add Path", systemImage: "plus.circle.fill")
                                .labelStyle(.iconOnly)
                                .font(.callout)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }

                    let paths = getPaths(from: item)

                    if paths.isEmpty {
                        Text("Click + to add project paths")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(0..<paths.count, id: \.self) { index in
                            HStack(spacing: 8) {
                                TextField(
                                    "/path/to/project",
                                    text: Binding(
                                        get: {
                                            let currentPaths = getPaths(from: item)
                                            return index < currentPaths.count
                                                ? currentPaths[index] : ""
                                        },
                                        set: { newValue in
                                            updatePath(at: index, with: newValue, for: item)
                                        }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: "path-\(item.id)-\(index)")

                                Button("Browse...") {
                                    selectPath(at: index, for: item)
                                }
                                .controlSize(.small)

                                Button {
                                    removePath(at: index, from: item)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            if !isBrowser(item.bundleIdentifier) && !isIDE(item.bundleIdentifier) {
                Text("No configurable parameters for this app type")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Helper Functions

    private func formatParameters(_ params: [String: String]) -> String {
        let urls = params.filter { $0.key.starts(with: "url") }.count
        let paths = params.filter { $0.key.starts(with: "path") }.count

        var parts: [String] = []
        if urls > 0 {
            parts.append("\(urls) URL\(urls == 1 ? "" : "s")")
        }
        if paths > 0 {
            parts.append("\(paths) path\(paths == 1 ? "" : "s")")
        }

        return parts.isEmpty ? "" : parts.joined(separator: ", ")
    }

    // MARK: - URL Management Helpers

    private func getURLs(from item: TemplateItem) -> [String] {
        guard let params = item.parameters else { return [] }

        var urls: [(Int, String)] = []
        for (key, value) in params {
            if key.starts(with: "url"), let indexStr = String(key.dropFirst(3)).nilIfEmpty,
                let index = Int(indexStr)
            {
                urls.append((index, value))
            }
        }

        return urls.sorted(by: { $0.0 < $1.0 }).map { $0.1 }
    }

    private func addURL(to item: TemplateItem) {
        guard let index = manager.templates.firstIndex(where: { $0.id == currentTemplate?.id }),
            let itemIndex = manager.templates[index].items.firstIndex(where: { $0.id == item.id })
        else { return }

        if manager.templates[index].items[itemIndex].parameters == nil {
            manager.templates[index].items[itemIndex].parameters = [:]
        }

        let urls = getURLs(from: item)
        let newIndex = urls.count

        manager.templates[index].items[itemIndex].parameters?["url\(newIndex)"] = ""
        manager.saveTemplates()
    }

    private func updateURL(at urlIndex: Int, with value: String, for item: TemplateItem) {
        guard let index = manager.templates.firstIndex(where: { $0.id == currentTemplate?.id }),
            let itemIndex = manager.templates[index].items.firstIndex(where: { $0.id == item.id })
        else { return }

        if manager.templates[index].items[itemIndex].parameters == nil {
            manager.templates[index].items[itemIndex].parameters = [:]
        }

        manager.templates[index].items[itemIndex].parameters?["url\(urlIndex)"] = value
        manager.saveTemplates()
    }

    private func removeURL(at urlIndex: Int, from item: TemplateItem) {
        guard let index = manager.templates.firstIndex(where: { $0.id == currentTemplate?.id }),
            let itemIndex = manager.templates[index].items.firstIndex(where: { $0.id == item.id })
        else { return }

        // Get all URLs
        var urls = getURLs(from: item)
        urls.remove(at: urlIndex)

        // Clear all URL parameters
        manager.templates[index].items[itemIndex].parameters?.keys.filter { $0.starts(with: "url") }
            .forEach {
                manager.templates[index].items[itemIndex].parameters?[$0] = nil
            }

        // Re-add with renumbered indices
        for (newIndex, url) in urls.enumerated() {
            manager.templates[index].items[itemIndex].parameters?["url\(newIndex)"] = url
        }

        if manager.templates[index].items[itemIndex].parameters?.isEmpty == true {
            manager.templates[index].items[itemIndex].parameters = nil
        }

        manager.saveTemplates()
    }

    // MARK: - Path Management Helpers

    private func getPaths(from item: TemplateItem) -> [String] {
        guard let params = item.parameters else { return [] }

        var paths: [(Int, String)] = []
        for (key, value) in params {
            if key.starts(with: "path"), let indexStr = String(key.dropFirst(4)).nilIfEmpty,
                let index = Int(indexStr)
            {
                paths.append((index, value))
            }
        }

        return paths.sorted(by: { $0.0 < $1.0 }).map { $0.1 }
    }

    private func addPath(to item: TemplateItem) {
        guard let index = manager.templates.firstIndex(where: { $0.id == currentTemplate?.id }),
            let itemIndex = manager.templates[index].items.firstIndex(where: { $0.id == item.id })
        else { return }

        if manager.templates[index].items[itemIndex].parameters == nil {
            manager.templates[index].items[itemIndex].parameters = [:]
        }

        let paths = getPaths(from: item)
        let newIndex = paths.count

        manager.templates[index].items[itemIndex].parameters?["path\(newIndex)"] = ""
        manager.saveTemplates()
    }

    private func updatePath(at pathIndex: Int, with value: String, for item: TemplateItem) {
        guard let index = manager.templates.firstIndex(where: { $0.id == currentTemplate?.id }),
            let itemIndex = manager.templates[index].items.firstIndex(where: { $0.id == item.id })
        else { return }

        if manager.templates[index].items[itemIndex].parameters == nil {
            manager.templates[index].items[itemIndex].parameters = [:]
        }

        manager.templates[index].items[itemIndex].parameters?["path\(pathIndex)"] = value
        manager.saveTemplates()
    }

    private func removePath(at pathIndex: Int, from item: TemplateItem) {
        guard let index = manager.templates.firstIndex(where: { $0.id == currentTemplate?.id }),
            let itemIndex = manager.templates[index].items.firstIndex(where: { $0.id == item.id })
        else { return }

        // Get all paths
        var paths = getPaths(from: item)
        paths.remove(at: pathIndex)

        // Clear all path parameters
        manager.templates[index].items[itemIndex].parameters?.keys.filter {
            $0.starts(with: "path")
        }.forEach {
            manager.templates[index].items[itemIndex].parameters?[$0] = nil
        }

        // Re-add with renumbered indices
        for (newIndex, path) in paths.enumerated() {
            manager.templates[index].items[itemIndex].parameters?["path\(newIndex)"] = path
        }

        if manager.templates[index].items[itemIndex].parameters?.isEmpty == true {
            manager.templates[index].items[itemIndex].parameters = nil
        }

        manager.saveTemplates()
    }

    private func selectPath(at pathIndex: Int, for item: TemplateItem) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        panel.begin { [weak manager] response in
            guard response == .OK, let url = panel.url, let manager = manager else { return }

            // Find the template and item to update
            if let templateIndex = manager.templates.firstIndex(where: {
                $0.id == self.currentTemplate?.id
            }),
                let itemIndex = manager.templates[templateIndex].items.firstIndex(where: {
                    $0.id == item.id
                })
            {

                if manager.templates[templateIndex].items[itemIndex].parameters == nil {
                    manager.templates[templateIndex].items[itemIndex].parameters = [:]
                }

                manager.templates[templateIndex].items[itemIndex].parameters?["path\(pathIndex)"] =
                    url.path
                manager.saveTemplates()
            }
        }
    }

    private func shouldShowParameterEditor(bundleId: String) -> Bool {
        isBrowser(bundleId) || isIDE(bundleId)
    }

    private func isBrowser(_ bundleId: String) -> Bool {
        let lower = bundleId.lowercased()
        return lower.contains("chrome") || lower.contains("safari") || lower.contains("firefox")
            || lower.contains("edge") || lower.contains("arc") || lower.contains("browser")
    }

    private func isIDE(_ bundleId: String) -> Bool {
        let lower = bundleId.lowercased()

        // Check specific bundle IDs first (for apps with non-standard IDs like Cursor)
        if lower.contains("todesktop") {
            // Cursor uses ToDesktop and has random bundle IDs like com.todesktop.230313mzl4w4u92
            return true
        }

        // Check for known keywords in bundle IDs
        return lower.contains("code") || lower.contains("cursor") || lower.contains("antigravity")
            || lower.contains("xcode") || lower.contains("intellij") || lower.contains("fleet")
            || lower.contains("studio") || lower.contains("rider") || lower.contains("pycharm")
            || lower.contains("webstorm") || lower.contains("goland") || lower.contains("clion")
            || lower.contains("phpstorm") || lower.contains("rubymine") || lower.contains("appcode")
            || lower.contains("sublime") || lower.contains("atom") || lower.contains("vim")
            || lower.contains("emacs") || lower.contains("nano") || lower.contains("textmate")
            || lower.contains("nova") || lower.contains("bbedit") || lower.contains("coda")
            || lower.contains("espresso") || lower.contains("brackets") || lower.contains("editor")
            || lower.contains("zed") || lower.contains("lapce")
    }

    private func getIcon(for bundleId: String) -> NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }
}

// MARK: - Add App Sheet

struct AddAppSheet: View {
    @Binding var showingSheet: Bool
    @ObservedObject var runningAppsModel: RunningAppsModel
    var onAdd: (RunningApp) -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Add App to Template")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    showingSheet = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            List {
                Button {
                    selectAppFromFinder()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.title3)
                            .foregroundStyle(.blue)
                            .frame(width: 32)

                        Text("Select from Finder...")
                            .font(.body)

                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)

                Section("Running Apps") {
                    ForEach(runningAppsModel.apps) { app in
                        Button {
                            onAdd(app)
                            showingSheet = false
                        } label: {
                            HStack(spacing: 12) {
                                Image(nsImage: app.icon ?? NSImage())
                                    .resizable()
                                    .frame(width: 32, height: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                        .font(.body)

                                    if let bundleId = app.bundleIdentifier {
                                        Text(bundleId)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(height: 400)
        }
        .padding(24)
        .frame(width: 500)
    }

    private func selectAppFromFinder() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        panel.begin { response in
            if response == .OK, let url = panel.url {
                if let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier {
                    let name =
                        bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                        ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                        ?? url.deletingPathExtension().lastPathComponent

                    let app = RunningApp(
                        id: Int.random(in: 0...99999),
                        bundleIdentifier: bundleId,
                        name: name,
                        icon: NSWorkspace.shared.icon(forFile: url.path),
                        isActive: false,
                        pid: 0,
                        lastFocusTime: nil
                    )
                    onAdd(app)
                    showingSheet = false
                }
            }
        }
    }
}

// MARK: - String Extension

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
