//
//  ARGPTApp.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 5/1/23.
//

import Combine
import SwiftUI

@main
struct ARGPTApp: App {
    private let _settings = Settings()
    private let _chatMessageStore = ChatMessageStore()
    @ObservedObject private var _bluetooth = BluetoothManager(autoConnectByProximity: true)
    private var _controller: Controller!

    @UIApplicationDelegateAdaptor private var _appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(
                settings: _settings,
                chatMessageStore: _chatMessageStore,
                bluetooth: _bluetooth,
                controller: _controller
            )
        }
    }

    init() {
        _controller = Controller(settings: _settings, bluetooth: _bluetooth, messages: _chatMessageStore)

    }
}

//TODO: when factoring this out into a separate file, indicate that only ContentView may *enable* Bluetooth and settings menu (unpair) can disable it
//TODO: may want a top-level state variable of some sort for the views to monitor -- especially once we start working on DFU update

struct ContentView: View {
    @ObservedObject private var _settings: Settings
    private let _chatMessageStore: ChatMessageStore
    private let _bluetooth: BluetoothManager
    private let _controller: Controller

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
                        if !_bluetooth.enabled {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                if _showPairingView {
                                    _bluetooth.enabled = true
                                }
                            }
                        }
                    }
            } else {
                ChatView(
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
                        _bluetooth.enabled = true
                    }
                }
                .environmentObject(_chatMessageStore)
                .environmentObject(_settings)
                .environmentObject(_bluetooth)
            }
        }
        .onAppear {
            // Initially, bring up pairing view if no paired device
            _showPairingView = _settings.pairedDeviceID == nil
        }
        .onChange(of: _showPairingView) {
            let dismissed = $0 == false

            // Detect when pairing view was dismissed. If we were scanning but did not pair (user
            // forcibly dismissed us), stop scanning altogether
            if dismissed && _settings.pairedDeviceID == nil {
                _bluetooth.enabled = false
            }
        }
    }

    init(settings: Settings, chatMessageStore: ChatMessageStore, bluetooth: BluetoothManager, controller: Controller) {
        _settings = settings
        _chatMessageStore = chatMessageStore
        _bluetooth = bluetooth
        _controller = controller
    }
}
