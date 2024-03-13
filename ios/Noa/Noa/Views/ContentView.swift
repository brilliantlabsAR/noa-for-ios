//
//  ContentView.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 7/23/23.
//
//  Top-level application view.
//

import CoreBluetooth
import SwiftUI

struct ContentView: View {
    @ObservedObject private var _settings: Settings
    private let _chatMessageStore: ChatMessageStore
    @ObservedObject private var _frameController: FrameController

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            colorScheme == .dark ? Color(red: 28/255, green: 28/255, blue: 30/255).edgesIgnoringSafeArea(.all) : Color(red: 242/255, green: 242/255, blue: 247/255).edgesIgnoringSafeArea(.all)

            VStack {
                if isLoggedIn() {
                    MainAppView(settings: _settings, chatMessageStore: _chatMessageStore, frameController: _frameController)
                } else {
                    LoginView(settings: _settings)
                }
            }
        }
    }

    init(settings: Settings, chatMessageStore: ChatMessageStore, frameController: FrameController) {
        _settings = settings
        _chatMessageStore = chatMessageStore
        _frameController = frameController
    }

    private func isLoggedIn() -> Bool {
        return _settings.apiToken != nil
    }
}

struct ContentView_Previews: PreviewProvider {
    private static var _settings = Settings()
    private static var _chatMessageStore = ChatMessageStore()
    private static var _frameController = {
        return FrameController(settings: Self._settings, messages: Self._chatMessageStore)
    }()

    static var previews: some View {
        ContentView(
            settings: Self._settings,
            chatMessageStore: Self._chatMessageStore,
            frameController: Self._frameController
        )
    }
}

