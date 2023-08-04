//
//  PairingSheetView.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 7/23/23.
//

import SwiftUI

struct PopupDeviceView: View {
    @Binding var showDeviceSheet: Bool
    @Binding var deviceSheetType: DeviceSheetType
    @Binding var monocleWithinPairingRange: Bool
    @Binding var updateProgressPercent: Int
    private let _onConnectPressed: (() -> Void)?
    
    //Video logic
    @State private var triggerUpdate = false
    let videoURL = Bundle.main.url(forResource: "SpinningMonocle", withExtension: "mp4")!
    
    var body: some View {
        
        ZStack {
            
            // Cancel button
            VStack {
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
                        
                    }
                    .padding(.top, 35)
                    .padding(.trailing, 35)
                }
                Spacer()
            }
            
            // Other stuff
            VStack {
            
                Text(deviceSheetType == .pairing
                     ? "Bring your device close."
                     : "Updating Software \(updateProgressPercent)%")
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.black)
                    .padding(.top, 50)
                
                Spacer()
                    .overlay(
                        LoopingVideoPlayer(videoURL: videoURL)
                            .frame(width: 170, height: 170)
                            .onAppear {
                                triggerUpdate.toggle()
                            }
                            .id(triggerUpdate)
                    )
                
                Button(action: {
                    _onConnectPressed?()
                    showDeviceSheet = false // dismiss view
                    }) {
                        Text(deviceSheetType == .pairing
                             ? (monocleWithinPairingRange
                                ? "Monocle. Connect"
                                : "Searching")
                             : "Keep the app open")
                            .font(.system(size: 22, weight: .medium))
                            .frame(width: 306, height: 50)
                    }
                    .background(Color(red: 242/255, green: 242/255, blue: 247/255))
                    .foregroundColor(monocleWithinPairingRange ? .black : Color(red: 141/255, green: 141/255, blue: 147/255))
                    .cornerRadius(15)
                    .disabled(!monocleWithinPairingRange || deviceSheetType != .pairing)
                    .padding(.bottom, 40)
            }
        }
    }


    init(showDeviceSheet: Binding<Bool>, deviceSheetType: Binding<DeviceSheetType>, monocleWithinPairingRange: Binding<Bool>, updateProgressPercent: Binding<Int>, onConnectPressed: (() -> Void)?) {
        _showDeviceSheet = showDeviceSheet
        _deviceSheetType = deviceSheetType
        _monocleWithinPairingRange = monocleWithinPairingRange
        _updateProgressPercent = updateProgressPercent
        _onConnectPressed = onConnectPressed
    }
}


