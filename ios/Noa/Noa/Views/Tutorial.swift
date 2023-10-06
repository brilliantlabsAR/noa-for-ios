//
//  Tutorial.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 10/5/23.
//

func displayTutorialInChatWindow(chatMessageStore: ChatMessageStore) async throws {
    let messages = [
        "Hi, I'm Noa. Let's show you around 🙂",
        "Hold either of the touch pads and speak.\n\nAsk me any question, and I'll respond directly on your Monocle.",
        "I can also translate whatever I hear into English.\n\nToggle the translator mode from the menu like so.",
        "Did you know that I'm a fantastic artist? Tap then hold, and Monocle will take a picture before listening.\n\nAsk me how to change the image, and I'll return back a new image right here in the chat.",
        "To get started, you'll need an OpenAI API key. To create one, visit:\n\n[https://platform.openai.com](https://platform.openai.com)\n\nAdditionally, to use the AI art feature, you'll need a Stability AI key. Get it here:\n\n[https://platform.stability.ai](https://platform.stability.ai)",
        "Looks like you're all set!\n\nGo ahead. Ask me anything you'd like ☺️"
    ]

    let pause = UInt64(2 * 1_000_000_000)

    for message in messages {
        chatMessageStore.putMessage(Message(text: message, participant: .assistant))
        try Task.checkCancellation()
        try await Task.sleep(nanoseconds: pause)
    }
}
