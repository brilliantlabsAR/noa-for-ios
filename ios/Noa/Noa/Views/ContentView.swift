//
//  ContentView.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 7/23/23.
//
//  Top-level application view. Observers Controller (the app logic or "model", effectively) and
//  decides what to display.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var _settings: Settings
    private let _chatMessageStore: ChatMessageStore
    @ObservedObject private var _controller: Controller

    private var _tutorialTask: Task<(), Error>?

    /// Monocle state (as reported by Controller)
    @State private var _isMonocleConnected = false
    @State private var _monocleWithinPairingRange = false   // only updated when no Monocle yet paired

    /// Bluetooth state
    @State private var _bluetoothEnabled = false

    /// Controls whether device sheet displayed
    @State private var _showDeviceSheet = false

    /// Controls which device sheet is displayed, if showDeviceSheeet == true
    @State private var _deviceSheetType: DeviceSheetType = .pairing

    /// Update percentage
    @State private var _updateProgressPercent: Int = 0

    /// First time connected? If device was ever in unpaired state, this flag is set and a tutorial is displayed upon successful pairing.
    @State private var _firstTimeConnecting = false

    /// Translation mode state
    @State private var _mode: AIAssistant.Mode = .assistant

    var body: some View {
        VStack {
            if _showDeviceSheet {
                // This view shown until 1) device becomes paired or 2) forcible dismissed by
                // _showPairingView = false
                DeviceScreenView(
                    showDeviceSheet: $_showDeviceSheet,
                    deviceSheetType: $_deviceSheetType,
                    monocleWithinPairingRange: $_monocleWithinPairingRange,
                    updateProgressPercent: $_updateProgressPercent,
                    onConnectPressed: { [weak _controller] in
                        _controller?.connectToNearest()
                    }
                )
                .onAppear {
                    // Delay a moment before enabling Bluetooth scanning so we actually see
                    // the pairing dialog. Also ensure that by the time this callback fires,
                    // the user has not just aborted the procedure. Note this is called each
                    // time view appears.
                    if !_bluetoothEnabled {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            if _showDeviceSheet {
                                _bluetoothEnabled = true
                            }
                        }
                    }
                }
            } else {
                ChatView(
                    isMonocleConnected: $_isMonocleConnected,
                    bluetoothEnabled: $_bluetoothEnabled,
                    showPairingView: $_showDeviceSheet,
                    mode: $_mode,
                    onTextSubmitted: { [weak _controller] (query: String) in
                        _controller?.submitQuery(query: query)
                    },
                    onClearChatButtonPressed: { [weak _controller] in
                        _controller?.clearHistory()
                    }
                )
                .onAppear {
                    // If this view became active and we are paired, ensure we enable Bluetooth
                    // because it is disabled initially. When app first loads, even with a paired
                    // device, need to explicitly enabled.
                    if _settings.pairedDeviceID != nil {
                        _bluetoothEnabled = true
                    }
                }
                .environmentObject(_chatMessageStore)
                .environmentObject(_settings)
            }
        }
        .onAppear {
            // Initialize state
            _isMonocleConnected = _controller.isMonocleConnected
            _monocleWithinPairingRange = _controller.nearestMonocleID != nil
            _bluetoothEnabled = _controller.bluetoothEnabled
            _firstTimeConnecting = _controller.pairedMonocleID == nil

            // Do we need to bring up device sheet initially? Do so if no Monocle paired or
            // if somehow already in an update state
            let (showDeviceSheet, deviceSheetType) = decideShowDeviceSheet()
            _showDeviceSheet = showDeviceSheet
            _deviceSheetType = deviceSheetType
        }
        .onChange(of: _controller.isMonocleConnected) {
            // Sync connection state
            _isMonocleConnected = $0
        }
        .onChange(of: _controller.nearestMonocleID) {
            // Sync nearest Monocle device ID
            _monocleWithinPairingRange = $0 != nil
        }
        .onChange(of: _controller.bluetoothEnabled) {
            // Sync Bluetooth state
            _bluetoothEnabled = $0
        }
        .onChange(of: _bluetoothEnabled) {
            // Pass through to controller (will not cause a cycle because we monitor change only)
            _controller.bluetoothEnabled = $0
        }
        .onChange(of: _showDeviceSheet) {
            let dismissed = $0 == false

            // When enabled, update device sheet type
            if !dismissed {
                let (_, deviceSheetType) = decideShowDeviceSheet()
                _deviceSheetType = deviceSheetType
                return
            }

            // Cannot dismiss while updating
            if dismissed && isUpdating() {
                _showDeviceSheet = true
                return
            }

            // Detect when pairing view was dismissed. If we were scanning but did not pair (user
            // forcibly dismissed us), stop scanning altogether
            if dismissed && _settings.pairedDeviceID == nil {
                _bluetoothEnabled = false
            }
        }
        .onChange(of: _controller.monocleState) { (value: Controller.MonocleState) in
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
            let (showDeviceSheet, deviceSheetType) = decideShowDeviceSheet()
            _showDeviceSheet = showDeviceSheet
            _deviceSheetType = deviceSheetType
        }
        .onChange(of: _controller.updateProgressPercent) {
            _updateProgressPercent = $0
        }
        .onChange(of: _mode) {
            // Settings menu may change mode
            _controller.mode = $0
        }
    }

    init(settings: Settings, chatMessageStore: ChatMessageStore, controller: Controller) {
        _settings = settings
        _chatMessageStore = chatMessageStore
        _controller = controller
    }

    private func decideShowDeviceSheet() -> (Bool, DeviceSheetType) {
        if _settings.pairedDeviceID == nil {
            // No Monocle pair, show pairing sheet
            return (true, .pairing)
        }

        switch _controller.monocleState {
        case .notReady:
            return (false, .pairing)    // don't show pairing sheet if disconnected but paired
        case .updatingFirmware:
            return (true, .firmwareUpdate)
        case .updatingFPGA:
            return (true, .fpgaUpdate)
        case .ready:
            return (false, .pairing)    // device is connected and running
        }
    }

    private func isUpdating() -> Bool {
        return _controller.monocleState == .updatingFirmware || _controller.monocleState == .updatingFPGA
    }
}
