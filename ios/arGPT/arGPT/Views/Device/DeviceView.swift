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
    @Binding var updateProgressPercent: Int

    var body: some View {
        ZStack {
            VStack {
                VStack {
                    let light = Image("BrilliantLabsLogo")
                        .resizable()
                    let dark = Image("BrilliantLabsLogo_Dark")
                        .resizable()
                    ColorModeAdaptiveImage(light: light, dark: dark)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 12)
                        .position(x: 200, y: -10)
                    Text("arGPT")
                        .font(.system(size: 32, weight: .bold))
                        .position(x: 203,y:-77)

                    let message = chooseMessage(basedOn: deviceSheetType)
                    Text(message)
                        .font(.system(size: 17))
                        .multilineTextAlignment(.center)
                        .frame(width: 346, height: 87)
                        .position(x: 200, y: -60)
                }
                .padding(.top)  // needed to avoid hitting unsafe top area (e.g., dynamic island)
                .frame(width: 393, height: 351)
                VStack {
                    Spacer()
                        .sheet(isPresented: $showDeviceSheet) {
                            switch deviceSheetType {
                            case .pairing:
                                PairingSheetView(showDeviceSheet: $showDeviceSheet)
                                    .presentationDragIndicator(.hidden)
                                    .presentationDetents([.height(370)])
                                    .interactiveDismissDisabled(true)
                            case .firmwareUpdate:
                                UpdateSheetView(updating: "firmware", updateProgressPercent: $updateProgressPercent)
                                    .presentationDragIndicator(.hidden)
                                    .presentationDetents([.height(370)])
                                    .interactiveDismissDisabled(true)
                            case .fpgaUpdate:
                                UpdateSheetView(updating: "FPGA", updateProgressPercent: $updateProgressPercent)
                                    .presentationDragIndicator(.hidden)
                                    .presentationDetents([.height(370)])
                                    .interactiveDismissDisabled(true)
                            }
                        }
                }
            }
        }
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
            updateProgressPercent: .constant(50)
        )
    }
}
