//
//  MessageView.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/1/23.
//

import SwiftUI

struct MessageView: View {
    private var _currentMessage: Message

    var body: some View {
        HStack(alignment: .bottom, spacing: 15) {
            if _currentMessage.participant != .assistant {
                // User bubble pushed all the way to right, translator will be centered
                Spacer()
            }
            MessageContentView(message: _currentMessage)
            if _currentMessage.participant == .translator {
                Spacer()
            }
        }
    }

    public init(currentMessage: Message) {
        _currentMessage = currentMessage
    }
}

struct MessageView_Previews: PreviewProvider {
    static var previews: some View {
        MessageView(currentMessage: Message(content: "Hello from ChatGPT", typingInProgress: false, participant: Participant.assistant))

    }
}
