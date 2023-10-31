//
//  Tutorial.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 10/5/23.
//

import UIKit

func displayTutorialInChatWindow(chatMessageStore: ChatMessageStore) async throws {
    let messages: [(pause: Float, image: UIImage?, text: String)] = [
        ( pause: 2, image: nil, text: "Hi, I'm Noa. Let's show you around 🙂" ),
        ( pause: 5, image: UIImage(named: "Tutorial_2"), text: "Tap either of the touch pads and speak.\n\nAsk me any question, and I'll respond directly on your Monocle." ),
        ( pause: 5, image: UIImage(named: "Tutorial_3"), text: "I can also translate whatever I hear into English.\n\nToggle the translator mode from the menu like so." ),
        ( pause: 5, image: UIImage(named: "Tutorial_4"), text: "Did you know that I'm a fantastic artist? Tap then hold, and Monocle will take a picture before listening.\n\nAsk me how to change the image, and I'll return back a new image right here in the chat." ),
        ( pause: 0, image: nil, text: "Looks like you're all set!\n\nGo ahead. Ask me anything you'd like ☺️" )
    ]

    for (pause, image, text) in messages {
        chatMessageStore.putMessage(Message(text: text, picture: image, participant: .assistant))
        try Task.checkCancellation()
        try await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
    }
}
