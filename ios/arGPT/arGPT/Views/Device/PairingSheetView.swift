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
        
        ZStack {
            VStack {
                Text("Bring your device close.")
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(.bottom)
                    .padding(.top)
                    .overlay(
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
                        
                        }
                        .padding(.top, -5)
                        .padding(.leading, 275),
                        alignment: .topLeading
                    )

            

                LoopingVideoPlayer(videoURL: videoURL)
                    .frame(width: 150, height: 150)
                    .onAppear {
                        triggerUpdate.toggle()
                    }
                    .id(triggerUpdate) // This will re-create the LoopingVideoPlayer on update
                    .padding(.bottom, 20)

                Button(action: {
                    _onConnectPressed?()
                    showDeviceSheet = false // dismiss view
                }) {
                    Text(buttonName)
                        .font(.system(size: 22, weight: .medium))
                        .frame(width: 306, height: 50)
                }
                .background(Color(red: 242/255, green: 242/255, blue: 247/255))
                .foregroundColor(monocleWithinPairingRange ? .black : Color(red: 141/255, green: 141/255, blue: 147/255))
                .cornerRadius(15)
                .disabled(!monocleWithinPairingRange)
            }

            
        }
    }


    init(showDeviceSheet: Binding<Bool>, monocleWithinPairingRange: Binding<Bool>, onConnectPressed: (() -> Void)?) {
        _showDeviceSheet = showDeviceSheet
        _monocleWithinPairingRange = monocleWithinPairingRange
        _onConnectPressed = onConnectPressed
    }
}


