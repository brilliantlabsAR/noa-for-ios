//
//  PairingSheetView.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 7/23/23.
//

import SwiftUI

struct PairingSheetView: View {
    @Binding var showDeviceSheet: Bool
    @Binding var monocleWithinPairingRange: Bool
    private let _onConnectPressed: (() -> Void)?
    
    //Video logic
    @State private var triggerUpdate = false
    let videoURL = Bundle.main.url(forResource: "SpinningMonocle", withExtension: "mp4")!
    
    var body: some View {
        let buttonName = monocleWithinPairingRange ? "Monocle. Connect" : "Searching"
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
                .padding(.bottom)
//            Image("Monocle")
//                .resizable()
//                .aspectRatio(contentMode: .fit)
//                .frame(width: 306, height: 160)
//                .padding()

            LoopingVideoPlayer(videoURL: videoURL)
                .frame(width: 150, height: 150)
                .onAppear {
                    triggerUpdate.toggle()
                }
                .id(triggerUpdate) // This will re-create the LoopingVideoPlayer on update
                
            Button(action: {
                _onConnectPressed?()
                showDeviceSheet = false // dismiss view
            }) {
            Text(buttonName)
                .font(.system(size: 22, weight: .medium))
                .frame(width: 306, height: 50)
            }
//          .padding(EdgeInsets(top: 20, leading: 40, bottom: 20, trailing: 40))
//          .padding(.horizontal, 60)
            .background(Color(red: 242/255, green: 242/255, blue: 247/255))
            .foregroundColor(monocleWithinPairingRange ? .black : Color(red: 141/255, green: 141/255, blue: 147/255))
            .cornerRadius(15)
            .disabled(!monocleWithinPairingRange)
        }
    }

    init(showDeviceSheet: Binding<Bool>, monocleWithinPairingRange: Binding<Bool>, onConnectPressed: (() -> Void)?) {
        _showDeviceSheet = showDeviceSheet
        _monocleWithinPairingRange = monocleWithinPairingRange
        _onConnectPressed = onConnectPressed
    }
}


