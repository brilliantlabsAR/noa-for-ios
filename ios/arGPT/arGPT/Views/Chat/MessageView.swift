//
//  MessageView.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 5/1/23.
//

import SwiftUI

struct MessageView: View {
    private var _currentMessage: Message

    var body: some View {
        HStack(alignment: .bottom, spacing: 15) {
            if !_currentMessage.participant.isUser {
                if _currentMessage.participant.hasImage {
                }
            } else {
                // If this is the user, push the content all the way to the right
                Spacer()
            }
            MessageContentView(message: _currentMessage)
        }
    }

    public init(currentMessage: Message) {
        _currentMessage = currentMessage
    }
}

struct MessageView_Previews: PreviewProvider {
    static var previews: some View {
        MessageView(currentMessage: Message(content: "Hello from ChatGPT", typingInProgress: false, participant: Participant.chatGPT))

    }
}
