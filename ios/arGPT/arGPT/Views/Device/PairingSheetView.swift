//
//  PairingSheetView.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 7/23/23.
//

import SwiftUI

struct PairingSheetView: View {
    @Binding var showDeviceSheet: Bool

    var body: some View {
        let buttonName = "Searching"
        HStack {
            Spacer()
            Button(role: .cancel) {
                showDeviceSheet = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(.body))
                    .padding(EdgeInsets(top: 20, leading: 40, bottom: 20, trailing: 40))
            }
        }
        VStack {
            Text("Bring your device close.")
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
                .frame(width: 306, height: 29)

            Image("Monocle")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 306, height: 160)

            Button(action: {
                // No Action needed
            }) {
                Text(buttonName)
                    .font(.system(size: 22, weight: .medium))
            }
            .padding(EdgeInsets(top: 20, leading: 40, bottom: 20, trailing: 40))
            .padding(.horizontal, 60)
            .background(Color(red: 242/255, green: 242/255, blue: 247/255))
            .foregroundColor(Color(red: 142/255, green: 142/255, blue: 147/255))
            .cornerRadius(15)
        }
    }
}
