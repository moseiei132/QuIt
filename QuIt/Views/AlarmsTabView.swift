//
//  AlarmsTabView.swift
//  QuIt
//
//  Created by Antigravity on 04/01/2569 BE.
//

import SwiftUI

enum AlarmFilter: String, CaseIterable {
    case all = "All"
    case profiles = "Profiles"
    case templates = "Templates"
    
    var icon: String {
        switch self {
        case .all:
            return "clock"
        case .profiles:
            return "person.crop.circle"
        case .templates:
            return "list.bullet.rectangle"
        }
    }
}

struct AlarmsTabView: View {
    @ObservedObject private var alarmManager = AlarmManager.shared
    @ObservedObject private var excludedManager = ExcludedAppsManager.shared
    @ObservedObject private var templateManager = AppTemplateManager.shared

    @State private var showingAddAlarm = false
    @State private var editingAlarm: Alarm?
    @State private var selectedFilter: AlarmFilter = .all

    var filteredAlarms: [Alarm] {
        switch selectedFilter {
        case .all:
            return alarmManager.alarms
        case .profiles:
            return alarmManager.alarms.filter { $0.type == .profile }
        case .templates:
            return alarmManager.alarms.filter { $0.type == .template }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Alarms")
                .font(.title2)
                .fontWeight(.bold)

            Text("Schedule automatic profile switching or template launching")
                .font(.callout)
                .foregroundColor(.secondary)

            Divider()

            // Filter Picker
            Picker("", selection: $selectedFilter) {
                ForEach(AlarmFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 8)

            // Alarms List
            if filteredAlarms.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(filteredAlarms) { alarm in
                        AlarmRowView(
                            alarm: alarm,
                            onEdit: {
                                editingAlarm = alarm
                            },
                            onDelete: {
                                alarmManager.deleteAlarm(alarm)
                            },
                            onToggle: {
                                alarmManager.toggleAlarm(alarm)
                            })
                    }
                }
                .listStyle(.inset)
            }

            Spacer()

            // Snoozed Alarms Section
            if !alarmManager.snoozedAlarms.isEmpty {
                Divider()
                    .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Snoozed Alarms")
                        .font(.headline)
                        .padding(.horizontal, 16)

                    ForEach(alarmManager.snoozedAlarms) { snooze in
                        SnoozedAlarmRow(snooze: snooze)
                    }
                }
                .padding(.bottom, 16)
            }

            // Add Button
            Button(action: {
                showingAddAlarm = true
            }) {
                Label("Add Alarm", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(20)
        .sheet(isPresented: $showingAddAlarm) {
            AddEditAlarmView(
                alarm: nil,
                onSave: { alarm in
                    _ = alarmManager.addAlarm(alarm)
                    showingAddAlarm = false
                },
                onCancel: {
                    showingAddAlarm = false
                })
        }
        .sheet(item: $editingAlarm) { alarm in
            AddEditAlarmView(
                alarm: alarm,
                onSave: { updatedAlarm in
                    alarmManager.updateAlarm(updatedAlarm)
                    editingAlarm = nil
                },
                onCancel: {
                    editingAlarm = nil
                })
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            selectedFilter == .all ? "No Alarms" : "No \(selectedFilter.rawValue)",
            systemImage: selectedFilter.icon,
            description: Text(
                selectedFilter == .all
                    ? "Create an alarm to automatically execute actions at specific times"
                    : "No \(selectedFilter.rawValue.lowercased()) alarms configured"
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Alarm Row View

struct AlarmRowView: View {
    let alarm: Alarm
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggle: () -> Void

    @ObservedObject private var excludedManager = ExcludedAppsManager.shared
    @ObservedObject private var templateManager = AppTemplateManager.shared

    var targetName: String {
        alarm.getTargetName() ?? "Unknown"
    }

    var iconName: String {
        if alarm.autoExecute {
            return alarm.type == .profile ? "arrow.triangle.2.circlepath" : "play.circle"
        } else {
            return "bell"
        }
    }

    var iconColor: Color {
        if alarm.autoExecute {
            return alarm.type == .profile ? .blue : .purple
        } else {
            return .orange
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Toggle
            Toggle(
                "",
                isOn: Binding(
                    get: { alarm.isEnabled },
                    set: { _ in onToggle() }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            // Time
            Text(alarm.formattedTime)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(alarm.isEnabled ? .primary : .secondary)
                .frame(width: 80, alignment: .leading)

            // Type icon, target name, days, and mode
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    // Type indicator
                    Image(systemName: alarm.type.icon)
                        .font(.caption)
                        .foregroundColor(alarm.type == .profile ? .blue : .purple)
                        .frame(width: 16)

                    // Mode indicator
                    Image(systemName: iconName)
                        .font(.caption2)
                        .foregroundColor(iconColor)

                    Text(targetName)
                        .font(.body)
                }

                if !alarm.daysOfWeek.isEmpty {
                    Text(alarm.daysOfWeekString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Every day")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Actions with colors and spacing
            HStack(spacing: 12) {
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Edit alarm")

                Button(action: onDelete) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Delete alarm")
            }
        }
        .opacity(alarm.isEnabled ? 1.0 : 0.6)
    }
}

// MARK: - Add/Edit Alarm View

struct AddEditAlarmView: View {
    let alarm: Alarm?
    let onSave: (Alarm) -> Void
    let onCancel: () -> Void

    @ObservedObject private var excludedManager = ExcludedAppsManager.shared
    @ObservedObject private var templateManager = AppTemplateManager.shared

    @State private var selectedHour: Int = 9
    @State private var selectedMinute: Int = 0
    @State private var selectedType: AlarmType = .profile
    @State private var selectedTargetID: UUID?
    @State private var autoExecute: Bool = true
    @State private var selectedDays: Set<Int> = []

    private let hours = Array(0...23)
    private let minutes = Array(0...59)

    init(
        alarm: Alarm?, onSave: @escaping (Alarm) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.alarm = alarm
        self.onSave = onSave
        self.onCancel = onCancel

        // Initialize with appropriate default
        if let alarm = alarm {
            _selectedType = State(initialValue: alarm.type)
            _selectedTargetID = State(initialValue: alarm.targetID)
        } else {
            _selectedType = State(initialValue: .profile)
            _selectedTargetID = State(
                initialValue: ExcludedAppsManager.shared.profiles.first?.id)
        }
    }

    var availableTargets: [(id: UUID, name: String)] {
        switch selectedType {
        case .profile:
            return excludedManager.profiles.map { (id: $0.id, name: $0.name) }
        case .template:
            return templateManager.templates.map { (id: $0.id, name: $0.name) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            Text(alarm == nil ? "Add Alarm" : "Edit Alarm")
                .font(.title2)
                .fontWeight(.bold)

            Divider()

            // Type Picker (only for new alarms)
            if alarm == nil {
                Picker("", selection: $selectedType) {
                    Text(AlarmType.profile.displayName).tag(AlarmType.profile)
                    Text(AlarmType.template.displayName).tag(AlarmType.template)
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedType) {
                    // Reset target when type changes
                    switch selectedType {
                    case .profile:
                        selectedTargetID = excludedManager.profiles.first?.id
                    case .template:
                        selectedTargetID = templateManager.templates.first?.id
                    }
                }

                Divider()
            }

            // Time Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Time")
                    .font(.headline)

                HStack(spacing: 16) {
                    Picker("Hour", selection: $selectedHour) {
                        ForEach(hours, id: \.self) { hour in
                            Text(String(format: "%02d", hour)).tag(hour)
                        }
                    }
                    .frame(width: 80)
                    .labelsHidden()

                    Text(":")
                        .font(.title2)

                    Picker("Minute", selection: $selectedMinute) {
                        ForEach(minutes, id: \.self) { minute in
                            Text(String(format: "%02d", minute)).tag(minute)
                        }
                    }
                    .frame(width: 80)
                    .labelsHidden()
                }
            }

            Divider()

            // Target Picker
            VStack(alignment: .leading, spacing: 8) {
                Text(selectedType == .profile ? "Target Profile" : "Target Template")
                    .font(.headline)

                if availableTargets.isEmpty {
                    Text("No \(selectedType.rawValue)s available")
                        .font(.body)
                        .foregroundColor(.secondary)
                } else {
                    Picker("Target", selection: $selectedTargetID) {
                        ForEach(availableTargets, id: \.id) { target in
                            Text(target.name).tag(target.id as UUID?)
                        }
                    }
                    .labelsHidden()
                }
            }

            Divider()

            // Auto-execute Toggle
            Toggle(
                selectedType == .profile
                    ? "Auto-switch profile (no confirmation)"
                    : "Auto-launch template (no confirmation)",
                isOn: $autoExecute
            )
            .font(.body)

            Text(
                autoExecute
                    ? (selectedType == .profile
                        ? "Profile will switch automatically when alarm triggers"
                        : "Template will launch automatically when alarm triggers")
                    : "Shows notification with action button"
            )
            .font(.caption)
            .foregroundColor(.secondary)

            Divider()

            // Days of Week
            VStack(alignment: .leading, spacing: 12) {
                Text("Repeat on")
                    .font(.headline)

                // Quick select buttons
                HStack(spacing: 8) {
                    Button("Every day") {
                        selectedDays = []
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(selectedDays.isEmpty ? .blue : .gray)

                    Button("Weekdays") {
                        selectedDays = [2, 3, 4, 5, 6]  // Mon-Fri
                    }
                    .buttonStyle(.bordered)

                    Button("Weekends") {
                        selectedDays = [1, 7]  // Sat-Sun
                    }
                    .buttonStyle(.bordered)
                }

                // Individual day toggles
                HStack(spacing: 8) {
                    ForEach(
                        [("S", 1), ("M", 2), ("T", 3), ("W", 4), ("T", 5), ("F", 6), ("S", 7)],
                        id: \.1
                    ) { day in
                        Button(day.0) {
                            if selectedDays.contains(day.1) {
                                selectedDays.remove(day.1)
                            } else {
                                selectedDays.insert(day.1)
                            }
                        }
                        .frame(width: 36, height: 36)
                        .background(
                            selectedDays.isEmpty || selectedDays.contains(day.1)
                                ? Color.blue : Color.gray.opacity(0.2)
                        )
                        .foregroundColor(
                            selectedDays.isEmpty || selectedDays.contains(day.1)
                                ? .white : .secondary
                        )
                        .cornerRadius(18)
                    }
                }
            }

            Spacer()

            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(alarm == nil ? "Add Alarm" : "Save") {
                    saveAlarm()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedTargetID == nil || availableTargets.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500, height: 650)
        .onAppear {
            if let alarm = alarm {
                selectedHour = alarm.time.hour ?? 9
                selectedMinute = alarm.time.minute ?? 0
                selectedType = alarm.type
                selectedTargetID = alarm.targetID
                autoExecute = alarm.autoExecute
                selectedDays = alarm.daysOfWeek
            } else {
                selectedHour = 9
                selectedMinute = 0
                autoExecute = true
                selectedDays = []
                // selectedTargetID and selectedType already set in init
            }
        }
    }

    private func saveAlarm() {
        guard let targetID = selectedTargetID else { return }

        var dateComponents = DateComponents()
        dateComponents.hour = selectedHour
        dateComponents.minute = selectedMinute

        let newAlarm = Alarm(
            id: alarm?.id ?? UUID(),
            time: dateComponents,
            type: selectedType,
            targetID: targetID,
            isEnabled: true,
            autoExecute: autoExecute,
            daysOfWeek: selectedDays
        )

        onSave(newAlarm)
    }
}
