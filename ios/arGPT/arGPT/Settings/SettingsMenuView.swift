//
//  SettingsMenuView.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 7/10/23.
//

import SwiftUI

struct SettingsMenuView: View {
    @EnvironmentObject private var _settings: Settings
    @Binding private var popUpApiBox: Bool

    var body: some View {
        Menu {
            Button(action: {
                popUpApiBox = true
            }) {
                Label("Change API Key", systemImage: "person.circle")
            }
            Button(action: {
                _settings.setPairedDeviceID(nil)
            }) {
                Label("Unpair Monocle", systemImage: "person.circle")
                    .foregroundColor(Color.red)
            }
        } label: {
            Image(systemName: "gearshape.fill")
                .foregroundColor(Color(red: 87/255, green: 199/255, blue: 170/255))
        }
    }

    init(popUpApiBox: Binding<Bool>) {
        _popUpApiBox = popUpApiBox
    }
}

struct SettingsMenuView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsMenuView(popUpApiBox: .constant(false))
            .environmentObject(Settings())
    }
}
