//
//  Location.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 3/8/24.
//

import Foundation

struct Location: CustomStringConvertible {
    let latitude: Double
    let longitude: Double
    let address: String
    var description: String {
        return "[\(address)\(address.count > 0 ? " " : "")(\(latitude),\(longitude))]"
    }
}
