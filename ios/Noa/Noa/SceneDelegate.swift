//
//  SceneDelegate.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/11/23.
//

import UIKit

class SceneDelegate: NSObject, UIWindowSceneDelegate, ObservableObject {
    public func sceneDidBecomeActive(_ scene: UIScene) {
        print("[SceneDelegate] Became active")
    }

    public func sceneWillResignActive(_ scene: UIScene) {
        print("[SceneDelegate] Will resign active")
    }

    public func sceneDidEnterBackground(_ scene: UIScene) {
        print("[SceneDelegate] Entered background")
    }

    public func sceneWillEnterForeground(_ scene: UIScene) {
        print("[SceneDelegate] Will enter foreground")
    }
}
