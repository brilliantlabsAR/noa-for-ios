//
//  SettingsMenuView.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 7/10/23.
//

import SwiftUI

struct SettingsMenuView: View {
    @EnvironmentObject private var _settings: Settings
    @State private var _translateEnabled = false

    private let _onAssistantModeChanged: ((AIAssistant.Mode) ->Void)?
    private let _onPairToggled: ((Bool) -> Void)?

    var body: some View {
        Menu {
            let isDevicePaired = _settings.pairedDeviceID != nil

            Toggle(isOn: $_translateEnabled) {
                Label("Translate", systemImage: "globe")
            }
            .toggleStyle(.button)

            Button(role: isDevicePaired ? .destructive : .none, action: {
                _onPairToggled?(!isDevicePaired)
            }) {
                // Unpair/pair Monocle
                if isDevicePaired {
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
            _onAssistantModeChanged?(_translateEnabled ? .translator : .assistant)
        }
        .onChange(of: _translateEnabled) {
            _onAssistantModeChanged?($0 ? .translator : .assistant)
        }
    }

    init(onAssistantModeChanged: ((AIAssistant.Mode) ->Void)?, onPairToggled: ((Bool) -> Void)?) {
        _onAssistantModeChanged = onAssistantModeChanged
        _onPairToggled = onPairToggled
    }
}

struct SettingsMenuView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsMenuView(
            onAssistantModeChanged: { print("Assistant mode changed to: \($0)") },
            onPairToggled: { print("Pair toggled: \($0)") }
        )
            .environmentObject(Settings())
    }
}
