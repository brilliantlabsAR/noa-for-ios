//
//  AppDelegate.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/11/23.
//

import UIKit

class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    // Provide SceneDelegate to SwiftUI
    public func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = SceneDelegate.self
        }
        return configuration
    }

    public func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        print("[AppDelegate] Handle events for background session: \(identifier)")
    }
}
