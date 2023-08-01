//
//  DeviceScreenView.swift
//  arGPT
//
//  Created by Artur Burlakin on 6/29/23.
//
//  This is the initial view on a fresh start when Moncole is unpaired and is used for device-
//  related operations: pairing, firmware update, FPGA update. Specific sheets are used for each
//  case.
//
//  Resources
//  ---------
//  - "Computed State in SwiftUI view"
//    https://yoswift.dev/swiftui/computed-state/
//

import SwiftUI

/// Device sheet types
enum DeviceSheetType {
    case pairing
    case firmwareUpdate
    case fpgaUpdate
}

struct DeviceScreenView: View {
    @Binding var showDeviceSheet: Bool
    @Binding var deviceSheetType: DeviceSheetType
    @Binding var monocleWithinPairingRange: Bool
    @Binding var updateProgressPercent: Int
    @Environment(\.openURL) var openURL
    @Environment(\.colorScheme) var colorScheme

    private let _onConnectPressed: (() -> Void)?
    
    var body: some View {
        ZStack {
            VStack {
                VStack {
                    Group{
                        let light = Image("BrilliantLabsLogo")
                            .resizable()
                        let dark = Image("BrilliantLabsLogo_Dark")
                            .resizable()
                        ColorModeAdaptiveImage(light: light, dark: dark)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 12)
                            .position(x: 200, y: 100)
                        Text("arGPT")
                            .font(.system(size: 32, weight: .bold))
                            .position(x: 203,y:25)
                        let message = chooseMessage(basedOn: deviceSheetType)
                        Text(message)
                            .font(.system(size: 15))
                        //.multilineTextAlignment(.center)
                            .frame(width: 314, height: 60)
                            .position(x: 203,y: 25)
                    }
                    
                    VStack {
                        
                        let privacyPolicyText = "Be sure to read our [Privacy Policy](https://brilliant.xyz/pages/privacy-policy) as well as [Terms and Conditions](https://brilliant.xyz/pages/terms-conditions) before using arGPT."
                        Text(.init(privacyPolicyText))
                            .font(.system(size: 10))
                            .frame(width: 217)
                            .multilineTextAlignment(.center)
                            .accentColor(Color(red: 232/255, green: 46/255, blue: 135/255))
                            .lineSpacing(10)
                            .position(x: 200, y: 120)
                            
                    }
                    
                }
                .padding(.top)  // needed to avoid hitting unsafe top area (e.g., dynamic island)
                .frame(width: 393, height: 400)
               // .blur(radius: showDeviceSheet ? 10 : 0)
                .background(colorScheme == .dark ? Color(red: 28/255, green: 28/255, blue: 30/255) : Color(red: 242/255, green: 242/255, blue: 247/255))
                .ignoresSafeArea(.all)
                VStack {
                    if showDeviceSheet {
                        ZStack {
                            RoundedRectangle(cornerRadius: 40)
                                .fill(Color.white)
                                .padding(10)
                                .transition(.move(edge: .bottom))
                                .animation(.easeInOut(duration: 2.5),value: UUID())

                            if deviceSheetType == .pairing {
                                PairingSheetView(
                                    showDeviceSheet: $showDeviceSheet,
                                    monocleWithinPairingRange: $monocleWithinPairingRange,
                                    onConnectPressed: _onConnectPressed
                                )
                                    .foregroundColor(Color.black)
                            } else {
                                UpdateSheetView( updateProgressPercent: $updateProgressPercent)
                                    .foregroundColor(Color.black)
                            }
                        }
                    }
                }
                .padding(.bottom, 1)
                .ignoresSafeArea(.all)
            }
            .background(colorScheme == .dark ? Color(red: 28/255, green: 28/255, blue: 30/255) : Color(red: 242/255, green: 242/255, blue: 247/255))
        }
    }

    init(showDeviceSheet: Binding<Bool>, deviceSheetType: Binding<DeviceSheetType>, monocleWithinPairingRange: Binding<Bool>, updateProgressPercent: Binding<Int>, onConnectPressed: (() -> Void)?) {
        _showDeviceSheet = showDeviceSheet
        _deviceSheetType = deviceSheetType
        _monocleWithinPairingRange = monocleWithinPairingRange
        _updateProgressPercent = updateProgressPercent
        _onConnectPressed = onConnectPressed
    }

    private func chooseMessage(basedOn deviceSheetType: DeviceSheetType) -> String {
        switch deviceSheetType {
        case .pairing:
            return "Let’s pair your device. Take your Monocle out of the case and bring it close."
        case .firmwareUpdate:
            return "Let's update your Monocle firmware. Keep your Monocle nearby and make sure this app stays open."
        case .fpgaUpdate:
            return "Let's update your Monocle's FPGA. Keep your Monocle nearby and make sure this app stays open."
        }
    }
}

struct DeviceScreenView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceScreenView(
            showDeviceSheet: .constant(true),
            deviceSheetType: .constant(.fpgaUpdate),
            monocleWithinPairingRange: .constant(true),
            updateProgressPercent: .constant(50),
            onConnectPressed: { print("Connect pressed") }
        )
    }
}
