//
//  ModelIOView.swift
//  arGPT
//
//  Created by Artur Burlakin on 2023-07-26.
//

import SwiftUI
import SceneKit
import ModelIO
import SceneKit.ModelIO

struct ModelIOView: UIViewRepresentable {
    let modelName: String

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        let scene = SCNScene()
        sceneView.scene = scene
        sceneView.autoenablesDefaultLighting = true
        sceneView.allowsCameraControl = false
        
        
        
        guard let assetUrl = Bundle.main.url(forResource: "\(modelName)", withExtension: "stl") else {
            print("Failed to find model \(modelName).stl in the app bundle.")
            return sceneView
        }
        
        let asset = MDLAsset(url: assetUrl)
        guard let object = asset.object(at: 0) as? MDLMesh else {
            print("Failed to get mesh from asset.")
            return sceneView
        }

        let node = SCNNode(mdlObject: object)
        scene.rootNode.addChildNode(node)
        
        let rotation = SCNAction.rotateBy(x: 0, y: CGFloat(2 * Double.pi), z: 0, duration: 10)
        let continuousRotation = SCNAction.repeatForever(rotation)
        node.runAction(continuousRotation)

        return sceneView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}
