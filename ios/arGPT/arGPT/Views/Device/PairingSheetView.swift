//
//  PairingSheetView.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 7/23/23.
//

import SwiftUI
import SceneKit

struct PairingSheetView: View {
    @Binding var showDeviceSheet: Bool

    var body: some View {
        let buttonName = "Searching"
        HStack {
            Spacer()
            Button(action: {
                showDeviceSheet = false
            }) {
                ZStack {
                    Circle()
                        .fill(Color(red: 116/255, green: 116/255, blue: 128/255).opacity(0.08))
                        .frame(width: 22, height: 22)
                    
                    Image(systemName: "xmark")
                        .resizable()
                        .foregroundColor(Color(red: 116/255, green: 116/255, blue: 128/255))
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 10, height: 10)
                }
                .padding(.trailing, 20)
                .position(x:350 , y: 40)
            }
        }
        VStack {
            Text("Bring your device close.")
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
                .frame(width: 306, height: 29)

//            Image("Monocle")
//                .resizable()
//                .aspectRatio(contentMode: .fit)
//                .frame(width: 306, height: 160)
//                .padding()
            ModelIOView(modelName: "brilliantMonocle")
                .aspectRatio(contentMode: .fit)
                .frame(width: 306, height: 160)
                .padding(.bottom)
            
            Button(action: {
                // No Action needed
            }) {
                Text(buttonName)
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: 306, height: 50)
            }
//          .padding(EdgeInsets(top: 20, leading: 40, bottom: 20, trailing: 40))
//          .padding(.horizontal, 60)
            .background(Color(red: 242/255, green: 242/255, blue: 247/255))
            .foregroundColor(Color(red: 141/255, green: 141/255, blue: 147/255))
            .cornerRadius(15)
        }
    }
}
