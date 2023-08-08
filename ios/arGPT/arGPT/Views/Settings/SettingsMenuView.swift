//
//  SettingsMenuView.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 7/10/23.
//

import SwiftUI

struct SettingsMenuView: View {
    @EnvironmentObject private var _settings: Settings

    @Binding var popUpApiBox: Bool
    @Binding var showPairingView: Bool
    @Binding var bluetoothEnabled: Bool
    @Binding var mode: Controller.Mode

    var body: some View {
        Menu {
            let isMonoclePaired = _settings.pairedDeviceID != nil

            Button(action: {
                mode = mode == .assistant ? .translator : .assistant
            }) {
                if mode == .assistant {
                    Label("Enable Translation", systemImage: "person.line.dotted.person")
                } else {
                    Label("Disable Translation", systemImage: "person.line.dotted.person.fill")
                }
            }

            Button(action: {
                popUpApiBox = true
            }) {
                Label("Change API Key", systemImage: "person.circle")
            }

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
    }
}

struct SettingsMenuView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsMenuView(
            popUpApiBox: .constant(false),
            showPairingView: .constant(false),
            bluetoothEnabled: .constant(true),
            mode: .constant(.assistant)
        )
            .environmentObject(Settings())
    }
}
