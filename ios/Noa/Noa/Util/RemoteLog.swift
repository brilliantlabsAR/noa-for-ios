//
//  RemoteLog.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 3/1/24.
//

import Foundation

extension Util {
    static func remoteLog(_ message: String) {
        let url = URL(string: "http://31.41.59.265:8080/print")!

        let form = Util.MultipartForm(fields: [
            .init(name: "message", text: message)
        ])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data;boundary=\(form.boundary)", forHTTPHeaderField: "Content-Type")

        let task = URLSession.shared.uploadTask(with: request, from: form.serialize()) { data, response, error in
            if let error = error {
                print("[RemoteLog] Error: \(error)")
                return
            }
            guard let response = response as? HTTPURLResponse,
                (200...299).contains(response.statusCode) else {
                if let response = response as? HTTPURLResponse {
                    print("[RemoteLog] Error: Code \(response.statusCode)")
                } else {
                    print("[RemoteLog] Error: Unknown error trying to communicate with server")
                }
                return
            }
            print("[RemoteLog] Logged: \(message)")
        }
        task.resume()
    }
}
