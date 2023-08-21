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
