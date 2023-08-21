//
//  ChatMessageStore.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/2/23.
//

import Combine
import SwiftUI

class ChatMessageStore: ObservableObject {
    public var didChange = PassthroughSubject<Void, Never>()
    @Published public var messages: [Message] = []

    public func putMessage(_ message: Message) {
        if let lastMessage = messages.last, lastMessage.typingInProgress {
            // Only the last message may be "typing in progress" indicator until supplanted by any other message
            messages.removeLast()
        }
        messages.append(message)
        didChange.send()
    }

    public func clear() {
        messages.removeAll()
        didChange.send()
    }

    public func minutesElapsed(from fromIndex: Int, to toIndex: Int) -> Double {
        if fromIndex < 0 {
            return .infinity
        } else if toIndex >= messages.count {
            return 0
        }
        let delta = messages[fromIndex].timestamp.distance(to: messages[toIndex].timestamp)
        return delta / 60
    }
}
