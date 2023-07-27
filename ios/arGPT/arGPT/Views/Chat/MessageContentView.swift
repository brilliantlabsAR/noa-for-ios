// MessageContentView.swift
// arGPT
// Created by Bart Trzynadlowski on 5/1/23.
import SwiftUI

struct MessageContentView: View {
    private let _contentMessage: String
    private let _isUser: Bool
    private let _isTyping: Bool
    private let _backgroundColor: Color
    private let _fontColor: Color

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
                .foregroundColor(_fontColor)
                .background(
                    ChatBubbleShape(direction: _isUser ? .right : .left)
                        .fill(_backgroundColor)
                )
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
            _backgroundColor = isUser ? Color(red: 87/255, green: 199/255, blue: 170/255) : Color(red: 233/255, green: 233/255, blue: 235/255)
        }
        _fontColor = isUser ? Color(UIColor.white) : Color(UIColor.black)
    }
}

// Taken from this website https://prafullkumar77.medium.com/swiftui-creating-a-chat-bubble-like-imessage-using-path-and-shape-67cf23ccbf62

struct ChatBubbleShape: Shape {
    enum Direction {
        case left
        case right
    }
    
    let direction: Direction
    
    func path(in rect: CGRect) -> Path {
        return (direction == .left) ? getLeftBubblePath(in: rect) : getRightBubblePath(in: rect)
    }
    
    private func getLeftBubblePath(in rect: CGRect) -> Path {
            let width = rect.width
            let height = rect.height
            let path = Path { p in
                p.move(to: CGPoint(x: 25, y: height))
                p.addLine(to: CGPoint(x: width - 20, y: height))
                p.addCurve(to: CGPoint(x: width, y: height - 20),
                           control1: CGPoint(x: width - 8, y: height),
                           control2: CGPoint(x: width, y: height - 8))
                p.addLine(to: CGPoint(x: width, y: 20))
                p.addCurve(to: CGPoint(x: width - 20, y: 0),
                           control1: CGPoint(x: width, y: 8),
                           control2: CGPoint(x: width - 8, y: 0))
                p.addLine(to: CGPoint(x: 21, y: 0))
                p.addCurve(to: CGPoint(x: 4, y: 20),
                           control1: CGPoint(x: 12, y: 0),
                           control2: CGPoint(x: 4, y: 8))
                p.addLine(to: CGPoint(x: 4, y: height - 11))
                p.addCurve(to: CGPoint(x: 0, y: height),
                           control1: CGPoint(x: 4, y: height - 1),
                           control2: CGPoint(x: 0, y: height))
                p.addLine(to: CGPoint(x: -0.05, y: height - 0.01))
                p.addCurve(to: CGPoint(x: 11.0, y: height - 4.0),
                           control1: CGPoint(x: 4.0, y: height + 0.5),
                           control2: CGPoint(x: 8, y: height - 1))
                p.addCurve(to: CGPoint(x: 25, y: height),
                           control1: CGPoint(x: 16, y: height),
                           control2: CGPoint(x: 20, y: height))
                
            }
            return path
        }
        
        private func getRightBubblePath(in rect: CGRect) -> Path {
            let width = rect.width
            let height = rect.height
            let path = Path { p in
                p.move(to: CGPoint(x: 25, y: height))
                p.addLine(to: CGPoint(x:  20, y: height))
                p.addCurve(to: CGPoint(x: 0, y: height - 20),
                           control1: CGPoint(x: 8, y: height),
                           control2: CGPoint(x: 0, y: height - 8))
                p.addLine(to: CGPoint(x: 0, y: 20))
                p.addCurve(to: CGPoint(x: 20, y: 0),
                           control1: CGPoint(x: 0, y: 8),
                           control2: CGPoint(x: 8, y: 0))
                p.addLine(to: CGPoint(x: width - 21, y: 0))
                p.addCurve(to: CGPoint(x: width - 4, y: 20),
                           control1: CGPoint(x: width - 12, y: 0),
                           control2: CGPoint(x: width - 4, y: 8))
                p.addLine(to: CGPoint(x: width - 4, y: height - 11))
                p.addCurve(to: CGPoint(x: width, y: height),
                           control1: CGPoint(x: width - 4, y: height - 1),
                           control2: CGPoint(x: width, y: height))
                p.addLine(to: CGPoint(x: width + 0.05, y: height - 0.01))
                p.addCurve(to: CGPoint(x: width - 11, y: height - 4),
                           control1: CGPoint(x: width - 4, y: height + 0.5),
                           control2: CGPoint(x: width - 8, y: height - 1))
                p.addCurve(to: CGPoint(x: width - 25, y: height),
                           control1: CGPoint(x: width - 16, y: height),
                           control2: CGPoint(x: width - 20, y: height))
                
            }
            return path
        }
    }


struct MessageContentView_Previews: PreviewProvider {
    static var previews: some View {
        let msg = Message(content: "Hello from ChatGPT", typingInProgress: false, participant: Participant.chatGPT)
//        let msg = Message(content: "ignored", typingInProgress: true, participant: Participant.chatGPT)
        MessageContentView(message: msg)
    }
}
