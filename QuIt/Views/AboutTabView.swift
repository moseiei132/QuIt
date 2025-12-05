//
//  AboutTabView.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import SwiftUI

struct AboutTabView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About QuIt")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Version 1.0")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("QuIt helps you quickly quit multiple applications at once.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Permissions")
                    .font(.headline)

                Text(
                    "QuIt requires Automation permission to quit other apps. If apps won't quit, check System Settings → Privacy & Security → Automation."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(20)
    }
}

