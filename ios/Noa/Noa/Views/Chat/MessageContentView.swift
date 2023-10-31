//
//  MessageContentView.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/1/23.
//
// ChatBubble taken from here: https://prafullkumar77.medium.com/swiftui-creating-a-chat-bubble-like-imessage-using-path-and-shape-67cf23ccbf62
//

import SwiftUI

struct MessageContentView: View {
    private let _message: Message

    @Environment(\.colorScheme) var colorScheme

    public init(message: Message) {
        _message = message
    }

    private var backgroundColor: Color {
        if _message.isError {
            return Color(UIColor.systemRed)
        }

        if _message.participant == .translator {
            return Color(red: 89/255, green: 93/255, blue: 177/255)
        }

        if colorScheme == .dark {
            if _message.participant == .user {
                return Color(red: 116/255, green: 170/255, blue: 156/255)
            } else  {
                return Color(red: 38/255, green: 38/255, blue: 40/255)
            }
        } else {
            if _message.participant == .user {
                return Color(red: 87/255, green: 199/255, blue: 170/255)
            } else {
                return Color(red: 233/255, green: 233/255, blue: 235/255)
            }
        }
    }

    private var chatBubbleDirection: ChatBubbleShape.Direction {
        switch _message.participant {
        case .assistant:
            return .left
        case .user:
            return .right
        default:
            return .center
        }
    }
    
    var body: some View {
        let fontColor: Color = (_message.participant != .assistant || colorScheme == .dark) ? Color(UIColor.white) : Color(UIColor.black)
        
        return Group {
            if _message.typingInProgress {
                let staticDotColor = _message.participant == .user ? Color(UIColor.lightGray) : Color(UIColor.lightGray)
                let animatingDotColor = _message.participant == .user ? Color(UIColor.lightGray) : Color(UIColor.white)
                TypingIndicatorView(staticDotColor: staticDotColor, animatingDotColor: animatingDotColor)
                    .padding(10)
                    .background(backgroundColor)
                    .cornerRadius(10)
            } else {
                Text(.init(_message.text))  // .init() is needed to parse markdown
                    .padding(10)
                    .foregroundColor(fontColor)
                    .background(
                        ChatBubbleShape(direction: chatBubbleDirection)
                            .fill(backgroundColor)
                    )
            }
        }
    }
}

struct ChatBubbleShape: Shape {
    enum Direction {
        case left
        case right
        case center
    }
    
    let direction: Direction
    
    func path(in rect: CGRect) -> Path {
        switch direction {
        case .left:
            return getLeftBubblePath(in: rect)
        case .right:
            return getRightBubblePath(in: rect)
        case .center:
            return getBubbleNoTailPath(in: rect)
        }
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

        private func getBubbleNoTailPath(in rect: CGRect) -> Path {
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
                p.addCurve(to: CGPoint(x: width - 0, y: 20),
                           control1: CGPoint(x: width - 12 + 4, y: 0),
                           control2: CGPoint(x: width - 0, y: 8))

                p.addLine(to: CGPoint(x: width - 0, y: height - 20))
                p.addCurve(to: CGPoint(x: width - 21, y: height),
                           control1: CGPoint(x: width - 0, y: height - 20 + 12),
                           control2: CGPoint(x: width - 0 - 8, y: height))
            }
            return path
        }
    }


struct MessageContentView_Previews: PreviewProvider {
    static var previews: some View {
        let msg = Message(text: "Hello from ChatGPT", typingInProgress: false, participant: .translator)
//        let msg = Message(content: "ignored", typingInProgress: true, participant: Participant.chatGPT)
        MessageContentView(message: msg)
    }
}
