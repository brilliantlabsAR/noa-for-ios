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
    private let _bluetooth: AsyncBluetoothManager
    @State private var _nearbyDevices: [(peripheral: CBPeripheral, rssi: Float)] = []

    // Pairing and connection state
    @State private var connectButtonState: DeviceSheetConnectButtonState = .searching
    @State private var deviceSheetState: DeviceSheetState = .searching
    @State private var firstTimeConnecting = false         // if device was ever unpaired and is connected for first time, this is used to show tutorial
    @State private var isConnected = false
    @State private var _connectButtonPressed = false

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
                        _connectButtonPressed = true
                    },
                    onCancelPressed: {
                        deviceSheetState = .hidden
                    }
                )
            } else {
                ChatView(
                    isMonocleConnected: $isConnected,
                    onTextSubmitted: { (query: String) in
                        //_controller?.submitQuery(query: query)
                    },
                    onClearChatButtonPressed: {
                        //_controller?.clearHistory()
                    },
                    onAssistantModeChanged: { (mode: AIAssistant.Mode) in
                        //TODO
                    },
                    onPairToggled: { (pair: Bool) in
                        _settings.setPairedDeviceID(nil)
                        //stopBluetoothTask()
                        _bluetooth.disconnect()
                        if pair {
                            deviceSheetState = .searching
                        }
                    }
                )
                .environmentObject(_chatMessageStore)
                .environmentObject(_settings)
            }
        }
        .task {
            await scanForNearbyDevicesTask()
        }
        .task {
            await runBluetoothTask()
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
    }

    init(settings: Settings, chatMessageStore: ChatMessageStore, frameController: FrameController, bluetooth: AsyncBluetoothManager) {
        _settings = settings
        _chatMessageStore = chatMessageStore
        _frameController = frameController
        _bluetooth = bluetooth
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

    private func scanForNearbyDevicesTask() async {
        while true {
            for await devices in _bluetooth.discoveredDevices {
                _nearbyDevices = devices
            }
        }
    }

    private func runBluetoothTask() async {
        print("[Bluetooth Task] Started ")
        isConnected = false

        while true {
            do {
                let connection = try await connectToDevice()
                isConnected = true

                try await _frameController.loadScript(named: "states.lua", on: connection)
                try await _frameController.loadScript(named: "graphics.lua", on: connection)
                try await _frameController.loadScript(named: "audio.lua", on: connection)
                try await _frameController.loadScript(named: "photo.lua", on: connection)
                try await _frameController.loadScript(named: "main.lua", on: connection)

                print("Starting...")

                connection.send(text: "\u{4}")

                //connection.send(text: "print('hello, world!')")
                //try await _frameController.loadScript(named: "test.lua", on: connection, run: true)
                for try await data in connection.receivedData {
                    Util.hexDump(data)
                }
            } catch let error as AsyncBluetoothManager.StreamError {
                // Disconnection falls through to loop around again
                isConnected = false
                print("[Bluetooth Task] Connection lost: \(error.localizedDescription)")
            } catch is CancellationError {
                // Task was canceled, exit it entirely
                print("[Bluetooth Task] Task canceled!")
                break
            } catch {
                print("[Bluetooth Task] Unknown error: \(error.localizedDescription)")
            }
        }

        isConnected = false
        print("[Bluetooth Task] Finished")
    }

    // Finds and connects to a device. If paired, will search for that device. Otherwise, will
    // search for a nearby device and wait until the user confirms by explicitly pressing
    // "Connect". Not as complicated as it looks but the UI state management is messy. Attempts to
    // be nice by sleeping when possible and checks for cancellation between async methods that do
    // not throw. Because we don't currently ever cancel the Bluetooth task (it would be a real
    // mess to try to cancel/restart it), this could be eliminated.
    private func connectToDevice() async throws -> AsyncBluetoothManager.Connection {
        _connectButtonPressed = false
        connectButtonState = .searching

        // Keep trying until we connect
        while true {
            print("[Bluetooth Task] Begin search and connect procedure...")

            var chosenDevice: CBPeripheral?
            var buttonHysteresisTime = Date.distantPast

            while chosenDevice == nil {
                if let pairedDeviceID = _settings.pairedDeviceID {
                    // Paired case: wait for paired device to appear, auto-connect to it
                    if let targetDevice = _nearbyDevices.first(where: { $0.peripheral.identifier == pairedDeviceID })?.peripheral {
                        chosenDevice = targetDevice
                        if deviceSheetState != .hidden {
                            // If device sheet is shown, pause for a moment before auto-connecting
                            // so it doesn't flicker and can be seen.
                            try await Task.sleep(for: .seconds(1))
                        }
                        break
                    }
                    try await Task.sleep(for: .seconds(0.5))
                } else {
                    // Unpaired case: Check whether any device is within pairing range, then wait for
                    // user to explicitly press the Connect button on the device sheet. Note that
                    // devices are already sorted in descending RSSI order so we only need to check
                    // threshold.
                    let rssiThreshold: Float = -60
                    let candidateDevice = _nearbyDevices.first(where: { $0.rssi > rssiThreshold })
                    if Date.now > buttonHysteresisTime {
                        if candidateDevice != nil {
                            // Stay in this state a moment to prevent flicker near RSSI threshold
                            connectButtonState = .canConnect
                            buttonHysteresisTime = .now.addingTimeInterval(1)
                        } else {
                            connectButtonState = .searching
                            buttonHysteresisTime = .distantPast
                        }
                    }

                    // Wait for user button press to confirm connection (and pairing)
                    if _connectButtonPressed, let candidateDevice = candidateDevice {
                        chosenDevice = candidateDevice.peripheral
                        _settings.setPairedDeviceID(candidateDevice.peripheral.identifier)
                        break
                    }
                    _connectButtonPressed = false
                    
                    // Need real-time response (connect button) when device sheet is shown,
                    // otherwise should sleep
                    if deviceSheetState != .hidden {
                        await Task.yield()
                    } else {
                        try await Task.sleep(for: .seconds(1))
                    }
                }
            }

            // Cancellation must be checked between any awaits that don't throw
            try Task.checkCancellation()

            connectButtonState = .connecting
            if let connection = await _bluetooth.connect(to: chosenDevice!) {
                // Once connected, safe to hide the device sheet
                print("[Bluetooth Task] Connected successfully")
                try Task.checkCancellation()
                deviceSheetState = .hidden
                return connection
            }

            try await Task.sleep(for: .seconds(0.5))
            print("[Bluetooth Task] Connection to device failed! Starting over...")
        }
    }
}
