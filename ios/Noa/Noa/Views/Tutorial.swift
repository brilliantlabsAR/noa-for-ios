//
//  Tutorial.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 10/5/23.
//

import UIKit

func displayTutorialInChatWindow(chatMessageStore: ChatMessageStore) async throws {
    let messages: [(image: UIImage?, text: String)] = [
        ( image: nil, text: "Hi, I'm Noa. Let's show you around 🙂" ),
        ( image: UIImage(named: "Tutorial_2"), text: "Hold either of the touch pads and speak.\n\nAsk me any question, and I'll respond directly on your Monocle." ),
        ( image: UIImage(named: "Tutorial_3"), text: "I can also translate whatever I hear into English.\n\nToggle the translator mode from the menu like so." ),
        ( image: UIImage(named: "Tutorial_4"), text: "Did you know that I'm a fantastic artist? Tap then hold, and Monocle will take a picture before listening.\n\nAsk me how to change the image, and I'll return back a new image right here in the chat." ),
        ( image: UIImage(named: "Tutorial_5"), text: "To get started, you'll need an OpenAI API key. To create one, visit:\n\n[https://platform.openai.com](https://platform.openai.com)\n\nAdditionally, to use the AI art feature, you'll need a Stability AI key. Get it here:\n\n[https://platform.stability.ai](https://platform.stability.ai)" ),
        ( image: nil, text: "Looks like you're all set!\n\nGo ahead. Ask me anything you'd like ☺️" )
    ]

    let pause = UInt64(2 * 1_000_000_000)

    for (image, text) in messages {
        chatMessageStore.putMessage(Message(text: text, picture: image, participant: .assistant))
        try Task.checkCancellation()
        try await Task.sleep(nanoseconds: pause)
    }
}
