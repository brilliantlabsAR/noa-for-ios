//
//  SignOut.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 2/7/24.
//

import Foundation

func signOut(authorizationToken: String) {
    let requestHeader = [
        "Authorization": authorizationToken
    ]
    let url = URL(string: "https://api.brilliant.xyz/noa/signout")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = requestHeader
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            print("[SignOut] Error: Logout failed: \(error)")
            return
        }
        guard let response = response as? HTTPURLResponse,
            (200...299).contains(response.statusCode) else {
            if let response = response as? HTTPURLResponse {
                print("[SignOut] Error: Logout failed with code \(response.statusCode)")
            } else {
                print("[SignOut] Error: Logout failed due to unknown error comunicating with server")
            }
            return
        }
        if let mimeType = response.mimeType,
            mimeType == "application/json",
            let data = data,
            let dataString = String(data: data, encoding: .utf8) {
            print ("[SignOut] Received response: \(dataString)")
        }
    }
    task.resume()
}

