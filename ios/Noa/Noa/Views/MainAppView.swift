//
//  MainAppView.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 2/7/24.
//

import CoreBluetooth
import SwiftUI

struct MainAppView: View {
    @ObservedObject private var _settings: Settings
    private let _chatMessageStore: ChatMessageStore
    @ObservedObject private var _frameController: FrameController

    // Bluetooth
    @State private var _nearbyDevices: [(peripheral: CBPeripheral, rssi: Float)] = []

    // Pairing and connection state
    @State private var pairButtonState: DeviceSheetButtonState = .searching
    @State private var deviceSheetState: DeviceSheetState = .searching
    @State private var firstTimeConnecting = false  // if device was ever unpaired and is connected for first time, this is used to show tutorial

    var body: some View {
        VStack {
            if deviceSheetState != .hidden {
                // This view shown until 1) device becomes paired or 2) forcible dismissed by
                // deviceSheetState = .hidden
                DeviceScreenView(
                    deviceSheetState: $deviceSheetState,
                    pairButtonState: $pairButtonState,
                    updateProgressPercent: .constant(0),
                    onPairPressed: {
                        if let device = _frameController.nearbyUnpairedDevice {
                            _frameController.pair(to: device)
                            pairButtonState = .connecting
                        }
                    },
                    onCancelPressed: {
                        deviceSheetState = .hidden
                    }
                )
            } else {
                ChatView(
                    isConnected: $_frameController.isConnected,
                    onTextSubmitted: { (query: String) in
                        _frameController.submitQuery(query: query)
                    },
                    onClearChatButtonPressed: {
                        _frameController.clearHistory()
                    },
                    onAssistantModeChanged: { (mode: AIAssistant.Mode) in
                        //TODO
                    },
                    onPairToggled: { (pair: Bool) in
                        _settings.setPairedDeviceID(nil)
                        _frameController.disconnect()
                        if pair {
                            deviceSheetState = .searching
                        }
                    }
                )
                .environmentObject(_chatMessageStore)
                .environmentObject(_settings)
            }
        }
        .onAppear {
            firstTimeConnecting = true
        }
        .onChange(of: deviceSheetState) {
            let dismissed = $0 == .hidden

            // When enabled, update device sheet type
            if !dismissed {
                deviceSheetState = decideDeviceSheetState()
                return
            }

            // Cannot dismiss while updating
            if dismissed && isUpdating() {
                deviceSheetState = decideDeviceSheetState()
                return
            }
        }
        .onChange(of: _frameController.isConnected) { (isConnected: Bool) in
            if isConnected {
                deviceSheetState = .hidden
            } else {
                deviceSheetState = .searching
                pairButtonState = .searching
            }
        }
        .onChange(of: _frameController.nearbyUnpairedDevice) { (device: CBPeripheral?) in
            guard !_frameController.isConnected else { return }
            guard device != nil else {
                pairButtonState = .searching
                return
            }
            pairButtonState = .pair
        }
    }

    init(settings: Settings, chatMessageStore: ChatMessageStore, frameController: FrameController) {
        _settings = settings
        _chatMessageStore = chatMessageStore
        _frameController = frameController
    }

    private func decideDeviceSheetState() -> DeviceSheetState {
        if _settings.pairedDeviceID == nil {
            // No device paired, show pairing sheet
            return .searching
        }
        return .hidden
    }

    private func isUpdating() -> Bool {
        return false
    }
}
