//
//  APIs.swift
//  TowIt
//
//  Created by Rajesh Roy on 31/12/21.
//

import Foundation

// MARK: - Header for API class

func getHeader() -> [String: String] {
    let headerFieldtokenType = "Bearer "
//    print(["Authorization": "\(headerFieldtokenType)\(headerFielddeviceToken)"])
    return ["Authorization": ""]
}

// ,"AuthID": getUserId()
