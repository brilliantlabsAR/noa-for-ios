//
//  SettingsMenuView.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 7/10/23.
//

import SwiftUI

struct SettingsMenuView: View {
    @EnvironmentObject private var _settings: Settings
    @EnvironmentObject private var _bluetooth: BluetoothManager
    @Binding var popUpApiBox: Bool
    @Binding var showPairingView: Bool

    var body: some View {
        Menu {
            Button(action: {
                popUpApiBox = true
            }) {
                Label("Change API Key", systemImage: "person.circle")
            }
            Button(action: {
                if _settings.pairedDeviceID != nil {
                    // Unpair but do not go back to pairing screen just yet
                    _bluetooth.enabled = false  // must stop scanning because we will auto repair otherwise
                    _settings.setPairedDeviceID(nil)
                } else {
                    // Return to pairing screen only on explicit pairing request
                    showPairingView = true
                }
            }) {
                // Unpair/pair Monocle
                if _settings.pairedDeviceID != nil {
                    Label("Unpair Monocle", systemImage: "person.circle")
                        .foregroundColor(Color.red)
                } else {
                    Label("Pair Monocle", systemImage: "person.circle")
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
        SettingsMenuView(popUpApiBox: .constant(false), showPairingView: .constant(false))
            .environmentObject(Settings())
    }
}
