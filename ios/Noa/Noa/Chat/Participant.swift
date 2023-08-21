//
//  Participant.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/2/23.
//

import Foundation

struct Participant: Equatable {
    public var name: String
    public var imageName: String

    public var hasImage: Bool {
        return !imageName.isEmpty
    }

    public static let user = Participant(name: "Me", imageName: "MonocleIcon")
    public static let assistant = Participant(name: "Assistant", imageName: "ChatGPTIcon")
    public static let translator = Participant(name: "Translator", imageName: "ChatGPTIcon")
}
