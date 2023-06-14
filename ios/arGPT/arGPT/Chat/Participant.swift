//
//  Participant.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 5/2/23.
//

import Foundation

struct Participant {
    public var name: String
    public var imageName: String
    public var isUser: Bool = false

    public var hasImage: Bool {
        return !imageName.isEmpty
    }

    public static let user = Participant(name: "Me", imageName: "MonocleIcon", isUser: true)
    public static let chatGPT = Participant(name: "ChatGPT", imageName: "ChatGPTIcon", isUser: false)
}
