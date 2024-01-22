//
//  ContentView.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 7/23/23.
//
//  Top-level application view.
//

import CoreBluetooth
import Foundation
import SwiftUI

struct ContentView: View {
    @ObservedObject private var _settings: Settings
    private let _chatMessageStore: ChatMessageStore
    @ObservedObject private var _frameController: FrameController

    // Bluetooth
    @State private var _nearbyDevices: [(peripheral: CBPeripheral, rssi: Float)] = []

    // Pairing and connection state
    @State private var connectButtonState: DeviceSheetConnectButtonState = .searching
    @State private var deviceSheetState: DeviceSheetState = .searching
    @State private var firstTimeConnecting = false         // if device was ever unpaired and is connected for first time, this is used to show tutorial

    // Translation mode state
    @State private var _mode: AIAssistant.Mode = .assistant

    var body: some View {
        VStack {
            if deviceSheetState != .hidden {
                // This view shown until 1) device becomes paired or 2) forcible dismissed by
                // deviceSheetState = .hidden
                DeviceScreenView(
                    deviceSheetState: $deviceSheetState,
                    connectButtonState: $connectButtonState,
                    updateProgressPercent: .constant(0),
                    onConnectPressed: {
                        if let device = _frameController.nearbyUnpairedDevice {
                            _frameController.pair(to: device)
                            connectButtonState = .connecting
                        }
                    },
                    onCancelPressed: {
                        deviceSheetState = .hidden
                    }
                )
            } else {
                ChatView(
                    isMonocleConnected: $_frameController.isConnected,
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
            firstTimeConnecting = isUnpaired()
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
        /*
        .onChange(of: _controller.monocleState) { (value: MonocleController.MonocleState) in
            // Tutorial
            if _controller.pairedMonocleID == nil {
                _firstTimeConnecting = true
            } else if value == .ready && _firstTimeConnecting {
                // Connected. Do we need to display tutorial?
                Task {
                    try await displayTutorialInChatWindow(chatMessageStore: _chatMessageStore)
                }
                _firstTimeConnecting = false
            }

            // Device sheet?
            deviceSheetState = decideDeviceSheetState()
        }
        */
        .onChange(of: _mode) {
            // Settings menu may change mode
            //_controller.mode = $0
            _ = $0 // shut up for now
        }

        .onChange(of: _frameController.isConnected) { (isConnected: Bool) in
            if isConnected {
                deviceSheetState = .hidden
            } else {
                deviceSheetState = .searching
                connectButtonState = .searching
            }
        }
        .onChange(of: _frameController.nearbyUnpairedDevice) { (device: CBPeripheral?) in
            guard !_frameController.isConnected else { return }
            guard device != nil else {
                connectButtonState = .searching
                return
            }
            connectButtonState = .canConnect
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

        //TODO: state if not connected

        return .hidden
    }

    private func isUnpaired() -> Bool {
        return true
    }

    private func isUpdating() -> Bool {
        return false
    }
}
