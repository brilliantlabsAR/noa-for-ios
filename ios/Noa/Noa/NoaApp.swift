//
//  NoaApp.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/1/23.
//

import Combine
import GoogleSignIn
import SwiftUI

fileprivate let _settings = Settings()
fileprivate let _chatMessageStore = ChatMessageStore()
fileprivate var _frameController: FrameController?

@MainActor
func getFrameController() -> FrameController {
    if let frameController = _frameController {
        return frameController
    }
    _frameController = FrameController(settings: _settings, messages: _chatMessageStore)
    return _frameController!
}

class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Make sure Frame controller and its connection loop is restored. I do not think the
        // SwiftUI view is brought up on CoreBluetooth restore.
        _ = getFrameController()
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        print("[AppDelegate] Handle events for background session: \(identifier)")
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        var handled: Bool

        handled = GIDSignIn.sharedInstance.handle(url)
        if handled {
            return true
        }

        // Handle other custom URL types.

        // If not handled by this app, return false.
        return false
    }
}

@main
struct NoaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(
                settings: _settings,
                chatMessageStore: _chatMessageStore,
                frameController: getFrameController()
            )
        }
    }
}
