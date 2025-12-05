//
//  TimeoutControlsView.swift
//  QuIt
//
//  Created by Dulyawat on 5/12/2568 BE.
//

import SwiftUI

// Reusable timeout controls with hours and minutes
struct TimeoutControlsView: View {
    @Binding var timeout: TimeInterval
    let minimumValue: TimeInterval
    
    var body: some View {
        HStack(spacing: 16) {
            // Hours control
            HStack(spacing: 8) {
                Text("Hours:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 45, alignment: .trailing)
                
                TextField("0", value: Binding(
                    get: { Int(timeout) / 3600 },
                    set: { newHours in
                        let currentMinutes = (Int(timeout) % 3600) / 60
                        let newTotal = newHours * 3600 + currentMinutes * 60
                        timeout = TimeInterval(max(Int(minimumValue), newTotal))
                    }
                ), formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                    .multilineTextAlignment(.center)
                
                Stepper("", value: Binding(
                    get: { Int(timeout) / 3600 },
                    set: { newHours in
                        let currentMinutes = (Int(timeout) % 3600) / 60
                        let newTotal = newHours * 3600 + currentMinutes * 60
                        timeout = TimeInterval(max(Int(minimumValue), newTotal))
                    }
                ), in: 0...10)
                .labelsHidden()
            }
            
            // Minutes control
            HStack(spacing: 8) {
                Text("Minutes:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 55, alignment: .trailing)
                
                TextField("0", value: Binding(
                    get: { (Int(timeout) % 3600) / 60 },
                    set: { newMinutes in
                        let currentHours = Int(timeout) / 3600
                        let newTotal = currentHours * 3600 + newMinutes * 60
                        timeout = TimeInterval(max(Int(minimumValue), newTotal))
                    }
                ), formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                    .multilineTextAlignment(.center)
                
                Stepper("", value: Binding(
                    get: { (Int(timeout) % 3600) / 60 },
                    set: { newMinutes in
                        let currentHours = Int(timeout) / 3600
                        let newTotal = currentHours * 3600 + newMinutes * 60
                        timeout = TimeInterval(max(Int(minimumValue), newTotal))
                    }
                ), in: 0...59)
                .labelsHidden()
            }
        }
    }
}

