//
//  SignInOut.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 2/7/24.
//

import Foundation

fileprivate struct SignInResponse: Codable {
    let token: String
    let email: String
}

func signIn(with provider: SocialIdentityProvider, token code: String, userID: String?, fullName: String?, email: String?, completion: @escaping (String?, String?) -> Void) {
    let fields: [Util.MultipartForm.Field] = [
        .init(name: "id_token", text: code),
        .init(name: "name", text: fullName ?? ""),
        .init(name: "email", text: email ?? ""),
        .init(name: "social_type", text: provider.rawValue),
        .init(name: "social_id", text: userID ?? "")
    ]
    let form = Util.MultipartForm(fields: fields)

    let requestHeader = [
        "Content-Type": "multipart/form-data;boundary=\(form.boundary)"
    ]

    let url = URL(string: "https://api.brilliant.xyz/noa/signin")!

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = requestHeader
    request.httpBody = form.serialize()

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            print("[SignIn] Error: Sign-in failed: \(error)")
            DispatchQueue.main.async { completion(nil, nil) }
            return
        }

        guard let response = response as? HTTPURLResponse,
            (200...299).contains(response.statusCode) else {
            if let response = response as? HTTPURLResponse {
                print("[SignIn] Error: Sign-in failed with code \(response.statusCode)")
            } else {
                print("[SignIn] Error: Sign-in failed due to unknown error comunicating with server")
            }
            DispatchQueue.main.async { completion(nil, nil) }
            return
        }

        guard let data = data else {
            print("[SignIn] Error: Sign-in failed: No response data received")
            DispatchQueue.main.async { completion(nil, nil) }
            return
        }

        do {
            let response = try JSONDecoder().decode(SignInResponse.self, from: data)
            DispatchQueue.main.async { completion(response.token, response.email) }
        } catch {
            print("[SignIn] Error: Unable to decode sign-in response: \(error)")
            DispatchQueue.main.async { completion(nil, nil) }
        }
    }
    task.resume()
}

func signOut(apiToken: String) {
    let requestHeader = [
        "Authorization": apiToken
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

