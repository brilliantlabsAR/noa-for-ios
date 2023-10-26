//
//  SettingsMenuView.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 7/10/23.
//

import SwiftUI

struct SettingsMenuView: View {
    @EnvironmentObject private var _settings: Settings

    @Binding var showPairingView: Bool
    @Binding var bluetoothEnabled: Bool
    @Binding var mode: AIAssistant.Mode

    @State private var _translateEnabled = false

    var body: some View {
        Menu {
            let isMonoclePaired = _settings.pairedDeviceID != nil

            Toggle(isOn: $_translateEnabled) {
                Label("Translate", systemImage: "globe")
            }
            .toggleStyle(.button)

            Button(role: isMonoclePaired ? .destructive : .none, action: {
                if isMonoclePaired {
                    // Unpair
                    _settings.setPairedDeviceID(nil)
                }

                // Always return to pairing screen right after unpairing or when pairing requested
                showPairingView = true
            }) {
                // Unpair/pair Monocle
                if isMonoclePaired {
                    Label("Unpair Monocle", systemImage: "wake")
                } else {
                    Label("Pair Monocle", systemImage: "wake")
                }
            }
        } label: {
            Image(systemName: "gearshape.fill")
                .foregroundColor(Color(red: 87/255, green: 199/255, blue: 170/255))
        }
        .onAppear {
            _translateEnabled = mode == .translator
        }
        .onChange(of: _translateEnabled) {
            mode = $0 ? .translator : .assistant
        }
    }
}

struct SettingsMenuView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsMenuView(
            showPairingView: .constant(false),
            bluetoothEnabled: .constant(true),
            mode: .constant(.assistant)
        )
            .environmentObject(Settings())
    }
}
