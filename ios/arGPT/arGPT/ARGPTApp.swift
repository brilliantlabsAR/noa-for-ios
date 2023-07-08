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
    private let _debugTryAudio = true

    private let _settings = Settings()
    private let _chatMessageStore = ChatMessageStore()

    @ObservedObject private var _bluetooth = BluetoothManager(autoConnectByProximity: true)

    private var _subscribers = Set<AnyCancellable>()

    private var _controller: Controller?

    @UIApplicationDelegateAdaptor private var _appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            if _bluetooth.selectedDeviceID == nil {
                InitialView(pairedMonocleID: $_bluetooth.selectedDeviceID)
            } else {
                ChatView(
                    isMonocleConnected: $_bluetooth.isConnected,
                    pairedMonocleID: $_bluetooth.selectedDeviceID,
                    onTextSubmitted: { [weak _controller] (query: String) in
                        _controller?.submitQuery(query: query)
                    },
                    onClearChatButtonPressed: { [weak _controller] in
                        _controller?.clearHistory()
                    }
                )
                .environmentObject(_chatMessageStore)
                .environmentObject(_settings)
            }
        }
    }

    init() {
        _controller = Controller(settings: _settings, bluetooth: _bluetooth, messages: _chatMessageStore)
    }
}
