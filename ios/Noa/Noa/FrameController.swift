//
//  FrameController.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 12/27/23.
//

import CoreBluetooth
import Foundation

class FrameController: ObservableObject {
    static let serviceUUID = CBUUID(string: "7a230001-5475-a6a4-654c-8431f6ad49c4")
    static let rxUUID = CBUUID(string: "7a230002-5475-a6a4-654c-8431f6ad49c4")
    static let txUUID = CBUUID(string: "7a230003-5475-a6a4-654c-8431f6ad49c4")


}
