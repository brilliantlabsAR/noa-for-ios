//
//  NoaApp.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/1/23.
//

import Combine
import SwiftUI

@main
struct NoaApp: App {
    private let _settings = Settings()
    private let _chatMessageStore = ChatMessageStore()
    private let _bluetooth = AsyncBluetoothManager(
        service: FrameController.serviceUUID,
        rxCharacteristic: FrameController.rxUUID,
        txCharacteristic: FrameController.txUUID
    )
    private var _frameController: FrameController!

    @UIApplicationDelegateAdaptor private var _appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(
                settings: _settings,
                chatMessageStore: _chatMessageStore,
                frameController: _frameController,
                bluetooth: _bluetooth
            )
        }
    }

    init() {
        _frameController = FrameController()
    }
}
