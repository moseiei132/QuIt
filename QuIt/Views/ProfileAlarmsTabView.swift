//
//  ProfileAlarmsTabView.swift
//  QuIt
//
//  Created by Antigravity on 12/12/2568 BE.
//

import SwiftUI

struct ProfileAlarmsTabView: View {
    @ObservedObject private var alarmManager = ProfileAlarmManager.shared
    @ObservedObject private var excludedManager = ExcludedAppsManager.shared

    @State private var showingAddAlarm = false
    @State private var editingAlarm: ProfileAlarm?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Profile Alarms")
                .font(.title2)
                .fontWeight(.bold)

            Text("Schedule automatic profile switching at specific times")
                .font(.callout)
                .foregroundColor(.secondary)

            Divider()

            // Alarms List
            if alarmManager.alarms.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(alarmManager.alarms) { alarm in
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
                    .padding(.bottom, 8)
                }
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
                    alarmManager.addAlarm(alarm)
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
            "No Alarms",
            systemImage: "alarm",
            description: Text("Create an alarm to automatically switch profiles at specific times")
        )
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Alarm Row View

struct AlarmRowView: View {
    let alarm: ProfileAlarm
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggle: () -> Void

    @ObservedObject private var excludedManager = ExcludedAppsManager.shared

    private var profileName: String {
        excludedManager.profiles.first(where: { $0.id == alarm.targetProfileID })?.name ?? "Unknown"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Time and Days
            VStack(alignment: .leading, spacing: 4) {
                Text(alarm.formattedTime)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(alarm.daysOfWeekString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 120, alignment: .leading)

            Divider()

            // Profile
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(profileName)
                        .font(.body)
                        .fontWeight(.medium)
                }

                // Mode badge
                Text(alarm.autoSwitch ? "Auto-switch" : "Alert only")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        alarm.autoSwitch ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2)
                    )
                    .foregroundColor(alarm.autoSwitch ? .blue : .secondary)
                    .cornerRadius(4)
            }

            Spacer()

            // Toggle
            Toggle("", isOn: .constant(alarm.isEnabled))
                .labelsHidden()
                .onChange(of: alarm.isEnabled) {
                    onToggle()
                }

            // Actions
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .help("Edit alarm")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("Delete alarm")
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .opacity(alarm.isEnabled ? 1.0 : 0.5)
    }
}

// MARK: - Add/Edit Alarm View

struct AddEditAlarmView: View {
    let alarm: ProfileAlarm?
    let onSave: (ProfileAlarm) -> Void
    let onCancel: () -> Void

    @ObservedObject private var excludedManager = ExcludedAppsManager.shared

    @State private var selectedHour: Int = 9
    @State private var selectedMinute: Int = 0
    @State private var selectedProfileID: UUID?
    @State private var autoSwitch: Bool = true
    @State private var selectedDays: Set<Int> = []

    private let hours = Array(0...23)
    private let minutes = Array(0...59)  // 1-minute increments for precise timing

    init(
        alarm: ProfileAlarm?, onSave: @escaping (ProfileAlarm) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.alarm = alarm
        self.onSave = onSave
        self.onCancel = onCancel

        // Initialize selectedProfileID with a default value to avoid Picker warning
        _selectedProfileID = State(
            initialValue: alarm?.targetProfileID ?? ExcludedAppsManager.shared.profiles.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            Text(alarm == nil ? "Add Alarm" : "Edit Alarm")
                .font(.title2)
                .fontWeight(.bold)

            Divider()

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

            // Profile Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Target Profile")
                    .font(.headline)

                Picker("Profile", selection: $selectedProfileID) {
                    ForEach(excludedManager.profiles) { profile in
                        Text(profile.name).tag(profile.id as UUID?)
                    }
                }
                .labelsHidden()
            }

            Divider()

            // Auto-switch Toggle
            Toggle("Auto-switch profile (no confirmation)", isOn: $autoSwitch)
                .font(.body)

            Text(
                autoSwitch
                    ? "Profile will switch automatically" : "Shows notification with Switch button"
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
                .disabled(selectedProfileID == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500, height: 600)
        .onAppear {
            if let alarm = alarm {
                selectedHour = alarm.time.hour ?? 9
                selectedMinute = alarm.time.minute ?? 0
                selectedProfileID = alarm.targetProfileID
                autoSwitch = alarm.autoSwitch
                selectedDays = alarm.daysOfWeek
            } else {
                // selectedProfileID already set in init to first profile
                selectedHour = 9
                selectedMinute = 0
                autoSwitch = true
                selectedDays = []
            }
        }
    }

    private func saveAlarm() {
        guard let profileID = selectedProfileID else { return }

        var dateComponents = DateComponents()
        dateComponents.hour = selectedHour
        dateComponents.minute = selectedMinute

        let newAlarm = ProfileAlarm(
            id: alarm?.id ?? UUID(),
            time: dateComponents,
            targetProfileID: profileID,
            isEnabled: true,
            autoSwitch: autoSwitch,
            daysOfWeek: selectedDays
        )

        onSave(newAlarm)
    }
}
