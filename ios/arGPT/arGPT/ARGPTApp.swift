//
//  ARGPTApp.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 5/1/23.
//

//
// TODO:
// -----
// - Settings may be passed into chat view as environment object.
// - Bluetooth must not. Try to remove Bluetooth entirely from the app level and hide in Controller.
// - Step 1: Expose bluetooth state on Controller (connected, paired, etc.)
// - Step 2: Bluetooth enable -> @State variable on content view that is observed and used to poke Controller as needed.
// - ...
// - Can isMonocleConnected and pairedMonocleID be defined as bindings that only read and do not allow set?
//  

import Combine
import SwiftUI

@main
struct ARGPTApp: App {
    private let _settings = Settings()
    private let _chatMessageStore = ChatMessageStore()
    private var _controller: Controller!

    @UIApplicationDelegateAdaptor private var _appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(
                settings: _settings,
                chatMessageStore: _chatMessageStore,
                controller: _controller
            )
        }
    }

    init() {
        _controller = Controller(settings: _settings, messages: _chatMessageStore)
    }
}

//TODO: when factoring this out into a separate file, indicate that only ContentView may *enable* Bluetooth and settings menu (unpair) can disable it
//TODO: may want a top-level state variable of some sort for the views to monitor -- especially once we start working on DFU update

struct ContentView: View {
    @ObservedObject private var _settings: Settings
    private let _chatMessageStore: ChatMessageStore
    private let _controller: Controller

    /// Monocle state (as reported by Controller)
    @State private var _isMonocleConnected = false
    @State private var _pairedMonocleID: UUID?

    /// Bluetooth state
    @State private var _bluetoothEnabled = false

    /// Controls whether pairing view is displayed
    @State private var _showPairingView = false

    var body: some View {
        VStack {
            if _showPairingView && _settings.pairedDeviceID == nil {
                // This view shown until 1) device becomes paired or 2) forcible dismissed by
                // _showPairingView = false
                InitialView(showPairingView: $_showPairingView)
                    .onAppear {
                        // Delay a moment before enabling Bluetooth scanning so we actually see
                        // the pairing dialog. Also ensure that by the time this callback fires,
                        // the user has not just aborted the procedure.
                        if !_bluetoothEnabled {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                if _showPairingView {
                                    _bluetoothEnabled = true
                                    print("ENABLE")
                                }
                            }
                        }
                    }
            } else {
                ChatView(
                    isMonocleConnected: $_isMonocleConnected,
                    pairedMonocleID: $_pairedMonocleID,
                    bluetoothEnabled: $_bluetoothEnabled,
                    showPairingView: $_showPairingView,
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
            _pairedMonocleID = _controller.pairedMonocleID
            _bluetoothEnabled = _controller.bluetoothEnabled

            // Initially, bring up pairing view if no paired device
            _showPairingView = _settings.pairedDeviceID == nil
        }
        .onChange(of: _controller.isMonocleConnected) {
            // Sync connection state
            _isMonocleConnected = $0
        }
        .onChange(of: _controller.pairedMonocleID) {
            // Sync paired device ID
            _pairedMonocleID = $0
        }
        .onChange(of: _controller.bluetoothEnabled) {
            // Sync Bluetooth state
            _bluetoothEnabled = $0
        }
        .onChange(of: _bluetoothEnabled) {
            // Pass through to controller (will not cause a cycle because we monitor change only)
            _controller.bluetoothEnabled = $0
        }
        .onChange(of: _showPairingView) {
            let dismissed = $0 == false

            // Detect when pairing view was dismissed. If we were scanning but did not pair (user
            // forcibly dismissed us), stop scanning altogether
            if dismissed && _settings.pairedDeviceID == nil {
                _bluetoothEnabled = false
            }
        }
    }

    init(settings: Settings, chatMessageStore: ChatMessageStore, controller: Controller) {
        _settings = settings
        _chatMessageStore = chatMessageStore
        _controller = controller
    }
}
