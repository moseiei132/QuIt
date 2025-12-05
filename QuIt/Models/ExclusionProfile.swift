//
//  ExclusionProfile.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import Foundation

struct ExclusionProfile: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var excludedBundleIDs: Set<String>

    init(id: UUID = UUID(), name: String, excludedBundleIDs: Set<String> = []) {
        self.id = id
        self.name = name
        self.excludedBundleIDs = excludedBundleIDs
    }
}

