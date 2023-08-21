//
//  LoopingVideoPlayer.swift
//  Noa
//
//  Created by Artur Burlakin on 2023-07-26.
//
import SwiftUI
import AVFoundation
import AVKit

var playerLooperMap: [ObjectIdentifier: AVPlayerLooper] = [:]

struct LoopingVideoPlayer: UIViewControllerRepresentable {
    typealias UIViewControllerType = AVPlayerViewController

    let videoURL: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let queuePlayer = AVQueuePlayer()
        let playerViewController = AVPlayerViewController()
        playerViewController.player = queuePlayer
        playerViewController.showsPlaybackControls = false

        let playerItem = AVPlayerItem(url: videoURL)
        queuePlayer.insert(playerItem, after: nil) // Insert the item into the queue
        queuePlayer.actionAtItemEnd = .none

        // Loop the video using AVPlayerLooper
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
        playerLooperMap[ObjectIdentifier(queuePlayer)] = looper

        // Start the video playback automatically
        queuePlayer.play()

        return playerViewController
    }
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player?.replaceCurrentItem(with: AVPlayerItem(url: videoURL))
    }
}
