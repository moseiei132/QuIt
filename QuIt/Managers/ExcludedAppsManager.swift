//
//  ExcludedAppsManager.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import Combine
import Foundation

// Manager for excluded apps with persistence and profile support
class ExcludedAppsManager: ObservableObject {
    static let shared = ExcludedAppsManager()

    @Published var profiles: [ExclusionProfile] = []
    @Published var selectedProfileID: UUID? {
        didSet {
            saveSelectedProfile()
            NotificationCenter.default.post(name: .excludedAppsDidChange, object: nil)
        }
    }

    var currentProfile: ExclusionProfile? {
        if let selectedID = selectedProfileID {
            return profiles.first(where: { $0.id == selectedID })
        }
        return profiles.first
    }

    var excludedBundleIDs: Set<String> {
        currentProfile?.excludedBundleIDs ?? []
    }

    private let profilesKey = "excludedAppsProfiles"
    private let selectedProfileKey = "selectedExcludedAppsProfile"

    private init() {
        loadProfiles()

        // If no profiles exist, create a default one
        if profiles.isEmpty {
            let defaultProfile = ExclusionProfile(name: "Default", excludedBundleIDs: [])
            profiles = [defaultProfile]
            selectedProfileID = defaultProfile.id
            saveProfiles()
        } else {
            loadSelectedProfile()
        }
    }

    private func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: profilesKey),
            let decoded = try? JSONDecoder().decode([ExclusionProfile].self, from: data)
        {
            profiles = decoded
        }
    }

    private func saveProfiles() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(encoded, forKey: profilesKey)
        }
    }

    private func loadSelectedProfile() {
        if let uuidString = UserDefaults.standard.string(forKey: selectedProfileKey),
            let uuid = UUID(uuidString: uuidString),
            profiles.contains(where: { $0.id == uuid })
        {
            selectedProfileID = uuid
        } else {
            selectedProfileID = profiles.first?.id
        }
    }

    private func saveSelectedProfile() {
        if let selectedID = selectedProfileID {
            UserDefaults.standard.set(selectedID.uuidString, forKey: selectedProfileKey)
        }
    }

    func addExclusion(_ bundleID: String) {
        guard var profile = currentProfile,
            let index = profiles.firstIndex(where: { $0.id == profile.id })
        else { return }

        profile.excludedBundleIDs.insert(bundleID)
        profiles[index] = profile
        saveProfiles()
        objectWillChange.send()
        NotificationCenter.default.post(name: .excludedAppsDidChange, object: nil)
    }

    func removeExclusion(_ bundleID: String) {
        guard var profile = currentProfile,
            let index = profiles.firstIndex(where: { $0.id == profile.id })
        else { return }

        profile.excludedBundleIDs.remove(bundleID)
        profiles[index] = profile
        saveProfiles()
        objectWillChange.send()
        NotificationCenter.default.post(name: .excludedAppsDidChange, object: nil)
    }

    func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID = bundleID else { return false }
        return excludedBundleIDs.contains(bundleID)
    }

    func createProfile(name: String) {
        let newProfile = ExclusionProfile(name: name, excludedBundleIDs: [])
        profiles.append(newProfile)
        selectedProfileID = newProfile.id
        saveProfiles()
    }

    func deleteProfile(_ profile: ExclusionProfile) {
        guard profiles.count > 1 else { return }  // Keep at least one profile

        profiles.removeAll { $0.id == profile.id }

        if selectedProfileID == profile.id {
            selectedProfileID = profiles.first?.id
        }

        saveProfiles()
    }

    func renameProfile(_ profile: ExclusionProfile, to newName: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index].name = newName
        saveProfiles()
        objectWillChange.send()
    }

    func duplicateProfile(_ profile: ExclusionProfile) {
        let duplicate = ExclusionProfile(
            name: "\(profile.name) Copy",
            excludedBundleIDs: profile.excludedBundleIDs
        )
        profiles.append(duplicate)
        saveProfiles()
    }
}

