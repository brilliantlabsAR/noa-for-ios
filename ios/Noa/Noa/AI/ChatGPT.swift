//
//  ChatGPT.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/12/23.
//

import UIKit

public class ChatGPT: NSObject {
    public enum NetworkConfiguration {
        case normal
        case backgroundData
        case backgroundUpload
    }

    public enum Mode {
        case assistant
        case translator
    }

    private static let _maxTokens = 4000    // 4096 for gpt-3.5-turbo and larger for gpt-4, but we use a conservative number to avoid hitting that limit

    private var _session: URLSession!
    private var _completionByTask: [Int: (String, String, AIError?) -> Void] = [:]
    private var _tempFileURL: URL?

    private static let _assistantPrompt = "You are a smart assistant that answers all user queries, questions, and statements with a single sentence."
    private static let _translatorPrompt = "You are a smart assistant that translates user input to English. Translate as faithfully as you can and do not add any other commentary."

    private var _payload: [String: Any] = [
        "model": "gpt-3.5-turbo",
        "messages": [
            [
                "role": "system",
                "content": ""   // remember to set
            ]
        ]
    ]

    public init(configuration: NetworkConfiguration) {
        super.init()

        switch configuration {
        case .normal:
            _session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        case .backgroundUpload:
            // Background upload tasks use a file (uploadTask() can only be called from background
            // with a file)
            _tempFileURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
            fallthrough
        case .backgroundData:
            // Configure a URL session that supports background transfers
            let configuration = URLSessionConfiguration.background(withIdentifier: "ChatGPT-\(UUID().uuidString)")
            configuration.isDiscretionary = false
            configuration.shouldUseExtendedBackgroundIdleMode = true
            configuration.sessionSendsLaunchEvents = true
            configuration.allowsConstrainedNetworkAccess = true
            configuration.allowsExpensiveNetworkAccess = true
            _session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        }
    }

    public func clearHistory() {
        // To clear history, remove all but the very first message
        if var messages = _payload["messages"] as? [[String: String]],
           messages.count > 1 {
            messages.removeSubrange(1..<messages.count)
            _payload["messages"] = messages
            print("[ChatGPT] Cleared history")
        }
    }

    public func send(mode: Mode, audio: Data, apiKey: String, model: String, completion: @escaping (String, String, AIError?) -> Void) {
        let boundary = UUID().uuidString

        let requestHeader = [
            "Authorization": "5T4C58VZ5yEDmMU+0yu6MWbfJi1dhN4vwuGEFOT4/sh4Kk/3YKg0E8zqoRm+wq2MfnjVV3Y/wIusBnYNIqJdkw==",
            "Content-Type": "multipart/form-data;boundary=\(boundary)"
        ]

        _payload["model"] = model
        setSystemPrompt(for: mode)

//TODO: when text prompt mode is fixed, we need to make sure not to append user query a second time after extracting content! Can probably
        // just check to see if it's already there at the end of the message list
        //TODO: remember to do this when response received! need to distinguish between text and audio requests on reception
        //appendUserQueryToChatSession(query: query)

        let url = URL(string: "https://api.brilliant.xyz/noa/audio_gpt")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = requestHeader

        // Form data
        var formData = Data()

        // Conversation history thus far using "json" field
        if let historyPayload = try? JSONSerialization.data(withJSONObject: _payload) {
            formData.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
            formData.append("Content-Disposition:form-data;name=\"json\"\r\n".data(using: .utf8)!)
            formData.append("Content-Type:application/json\r\n\r\n".data(using: .utf8)!)
            formData.append(historyPayload)
            formData.append("\r\n".data(using: .utf8)!)
        }

        // Audio data representing next user query
        formData.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"audio\";filename=\"audio.m4a\"\r\n".data(using: .utf8)!)  //TODO: temperature?
        formData.append("Content-Type:audio/m4a\r\n\r\n".data(using: .utf8)!)
        formData.append(audio)
        formData.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        // If this is a background task using a file, write that file, else attach to request
        if let fileURL = _tempFileURL {
            //TODO: error handling
            try? formData.write(to: fileURL)
        } else {
            request.httpBody = formData
        }

        // Create task
        let task = _tempFileURL == nil ? _session.dataTask(with: request) : _session.uploadTask(with: request, fromFile: _tempFileURL!)

        // Associate completion handler with this task
        _completionByTask[task.taskIdentifier] = completion

        // Begin
        task.resume()
    }

    public func send(mode: Mode, query: String, apiKey: String, model: String, completion: @escaping (String, String, AIError?) -> Void) {
        let boundary = UUID().uuidString

        let requestHeader = [
            "Authorization": "5T4C58VZ5yEDmMU+0yu6MWbfJi1dhN4vwuGEFOT4/sh4Kk/3YKg0E8zqoRm+wq2MfnjVV3Y/wIusBnYNIqJdkw==",
            "Content-Type": "multipart/form-data;boundary=\(boundary)"
        ]

        _payload["model"] = model
        setSystemPrompt(for: mode)

        appendUserQueryToChatSession(query: query)

        let jsonPayload = try? JSONSerialization.data(withJSONObject: _payload)
        let url = URL(string: "https://api.brilliant.xyz/noa/chat_gpt")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = requestHeader

        // Form data
        var formData = Data()

        if let json = jsonPayload {
            formData.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
            formData.append("Content-Disposition:form-data;name=\"json\"\r\n".data(using: .utf8)!)
            formData.append("Content-Type:application/json\r\n\r\n".data(using: .utf8)!)
            formData.append(json)
            formData.append("\r\n".data(using: .utf8)!)
        }

        // If this is a background task using a file, write that file, else attach to request
        if let fileURL = _tempFileURL {
            //TODO: error handling
            try? formData.write(to: fileURL)
        } else {
            request.httpBody = formData
        }

        // Create task
        let task = _tempFileURL == nil ? _session.dataTask(with: request) : _session.uploadTask(with: request, fromFile: _tempFileURL!)

        // Associate completion handler with this task
        _completionByTask[task.taskIdentifier] = completion

        // Begin
        task.resume()
    }

    private func setSystemPrompt(for mode: Mode) {
        if var messages = _payload["messages"] as? [[String: String]],
           messages.count >= 1 {
            messages[0]["content"] = mode == .assistant ? Self._assistantPrompt : Self._translatorPrompt
            _payload["messages"] = messages
        }
    }

    private func appendUserQueryToChatSession(query: String) {
        if var messages = _payload["messages"] as? [[String: String]] {
            // Append user prompts to maintain some sort of state. Note that we do not send back the agent responses because
            // they won't add much.
            messages.append([ "role": "user", "content": "\(query)" ])
            _payload["messages"] = messages
        }
    }

    private func appendAIResponseToChatSession(response: String) {
        if var messages = _payload["messages"] as? [[String: String]] {
            messages.append([ "role": "assistant", "content": "\(response)" ])
            _payload["messages"] = messages
        }
    }

    private func extractContent(from data: Data) -> (Any?, AIError?, String?, String?) {
        do {
            let jsonString = String(decoding: data, as: UTF8.self)
            if jsonString.count > 0 {
                print("[ChatGPT] Response payload: \(jsonString)")
            }
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            if let response = json as? [String: AnyObject] {
                if let errorMessage = response["message"] as? String {
                   return (json, AIError.apiError(message: "Error from service: \(errorMessage)"), nil, nil)
                } else if let choices = response["choices"] as? [AnyObject],
                          choices.count > 0,
                          let first = choices[0] as? [String: AnyObject],
                          let message = first["message"] as? [String: AnyObject],
                          let assistantResponse = message["content"] as? String,
                          let userQuery = response["prompt"] as? String {
                    return (json, nil, userQuery, assistantResponse)
                }
            }
            print("[ChatGPT] Error: Unable to parse response")
        } catch {
            print("[ChatGPT] Error: Unable to deserialize response: \(error)")
        }
        return (nil, AIError.responsePayloadParseError, nil, nil)
    }

    private func extractTotalTokensUsed(from json: Any?) -> Int {
        if let json = json,
           let response = json as? [String: AnyObject],
           let usage = response["usage"] as? [String: AnyObject],
           let totalTokens = usage["total_tokens"] as? Int {
            return totalTokens
        }
        return 0
    }
}

extension ChatGPT: URLSessionDelegate {
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        let errorMessage = error == nil ? "unknown error" : error!.localizedDescription
        print("[ChatGPT] URLSession became invalid: \(errorMessage)")

        // Deliver error for all outstanding tasks
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for (_, completion) in self._completionByTask {
                completion("", "", AIError.clientSideNetworkError(error: error))
            }
            _completionByTask = [:]
        }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        print("[ChatGPT] URLSession finished events")
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        print("[ChatGPT] URLSession received challenge")
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            print("[ChatGPT] URLSession unable to use credential")
        }
    }
}

extension ChatGPT: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome streamTask: URLSessionStreamTask) {
        print("[ChatGPT] URLSessionDataTask became stream task")
        streamTask.resume()
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome downloadTask: URLSessionDownloadTask) {
        print("[ChatGPT] URLSessionDataTask became download task")
        downloadTask.resume()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        print("[ChatGPT] URLSessionDataTask received challenge")
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            print("[ChatGPT] URLSessionDataTask unable to use credential")

            // Deliver error
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let completion = self._completionByTask[task.taskIdentifier] {
                    completion("", "", AIError.urlAuthenticationFailed)
                    self._completionByTask.removeValue(forKey: task.taskIdentifier)
                }
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Original request was redirected somewhere else. Create a new task for redirection.
        if let urlString = request.url?.absoluteString {
            print("[ChatGPT] URLSessionDataTask redirected to \(urlString)")
        } else {
            print("[ChatGPT] URLSessionDataTask redirected")
        }

        // New task
        let newTask = self._session.dataTask(with: request)

        // Replace completion
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let completion = self._completionByTask[task.taskIdentifier] {
                self._completionByTask.removeValue(forKey: task.taskIdentifier) // out with the old
                self._completionByTask[newTask.taskIdentifier] = completion     // in with the new
            }
        }

        // Continue with new task
        newTask.resume()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("[ChatGPT] URLSessionDataTask failed to complete: \(error.localizedDescription)")
        } else {
            // Error == nil should indicate successful completion
            print("[ChatGPT] URLSessionDataTask finished")
        }

        // If there really was no error, we should have received data, triggered the completion,
        // and removed the completion. If it's still hanging around, there must be some unknown
        // error or I am interpreting the task lifecycle incorrectly.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let completion = self._completionByTask[task.taskIdentifier] {
                completion("", "", AIError.clientSideNetworkError(error: error))
                self._completionByTask.removeValue(forKey: task.taskIdentifier)
            }
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Assume that regardless of any error (including non-200 status code), the didCompleteWithError
        // delegate method will eventually be called and we can report the error there
        print("[ChatGPT] URLSessionDataTask received response headers")
        guard let response = response as? HTTPURLResponse else {
            print("[ChatGPT] URLSessionDataTask received unknown response type")
            return
        }
        print("[ChatGPT] URLSessionDataTask received response code \(response.statusCode)")
        completionHandler(URLSession.ResponseDisposition.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let (json, contentError, userPrompt, response) = extractContent(from: data)
        let userPromptString = userPrompt ?? ""
        let responseString = response ?? "" // if response is nill, contentError will be set
        let totalTokensUsed = extractTotalTokensUsed(from: json)

        // Deliver response and append to chat session
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Append to chat session to maintain running dialog unless we've exceeded the context
            // window
            if totalTokensUsed >= Self._maxTokens {
                clearHistory()
                print("[ChatGPT] Cleared context history because total tokens used reached \(totalTokensUsed)")
            } else {
                // Append the user prompt
                if userPrompt != nil {
                    appendUserQueryToChatSession(query: userPromptString)
                }

                // And also the response
                if let response = response {
                    appendAIResponseToChatSession(response: response)
                }
            }

            // Deliver response
            if let completion = self._completionByTask[dataTask.taskIdentifier] {
                // User prompt delivered in
                completion(userPromptString, responseString, contentError)
                self._completionByTask.removeValue(forKey: dataTask.taskIdentifier)
            } else {
                print("[ChatGPT]: Error: No completion found for task \(dataTask.taskIdentifier)")
            }
        }
    }
}
