//
//  MessageContentView.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 5/1/23.
//

import SwiftUI

struct MessageContentView: View {
    private let _contentMessage: String
    private let _isUser: Bool
    private let _isTyping: Bool
    private let _backgroundColor: Color
    

    var body: some View {
        if _isTyping {
            let staticDotColor = _isUser ? Color(UIColor.lightGray) : Color(UIColor.lightGray)
            let animatingDotColor = _isUser ? Color(UIColor.lightGray) : Color(UIColor.white)
            TypingIndicatorView(staticDotColor: staticDotColor, animatingDotColor: animatingDotColor)
                .padding(10)
                .background(_backgroundColor)
                .cornerRadius(10)
        } else {
            Text(_contentMessage)
                .padding(10)
                .foregroundColor(Color.white)
                .background(_backgroundColor)
                .cornerRadius(10)
        }
    }

    public init(message: Message) {
        let isUser = message.participant.isUser
        _contentMessage = message.content
        _isUser = message.participant.isUser
        _isTyping = message.typingInProgress
        if message.isError {
            _backgroundColor = Color(UIColor.systemRed)
        } else {
            _backgroundColor = isUser ? Color(UIColor.systemBlue) : Color(UIColor.darkGray)
        }
    }
}

struct MessageContentView_Previews: PreviewProvider {
    static var previews: some View {
        let msg = Message(content: "Hello from ChatGPT", typingInProgress: false, participant: Participant.chatGPT)
        //let msg = Message(content: "ignored", typingInProgress: true, participant: Participant.chatGPT)
        MessageContentView(message: msg)
    }
}
