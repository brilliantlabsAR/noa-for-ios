//
//  ChatGPT.swift
//  MyChatGPT
//
//  Created by Techno Exponent on 24/04/23.
//

import Foundation
import SwiftUI
import Combine


struct ChatMessage {
    let id: String
    let content: String
    let dateCreated: Date
    let sender: MessageSender
}

enum MessageSender {
    case me
    case gpt
}

extension ChatMessage {
    static let sampleMessages = [
        ChatMessage(id: UUID().uuidString, content: "Sample message from me", dateCreated: Date(), sender: .me),
        ChatMessage(id: UUID().uuidString, content: "Sample message from gpt", dateCreated: Date(), sender: .gpt),
        ChatMessage(id: UUID().uuidString, content: "Sample message from me", dateCreated: Date(), sender: .me),
        ChatMessage(id: UUID().uuidString, content: "Sample message from gpt", dateCreated: Date(), sender: .gpt),
    ]
}
