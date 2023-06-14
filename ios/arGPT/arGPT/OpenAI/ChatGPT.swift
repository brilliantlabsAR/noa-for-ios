//
//  ChatGPT.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 5/12/23.
//

import UIKit

public class ChatGPT: NSObject {
    public enum Configuration {
        case normal
        case backgroundData
        case backgroundUpload
    }

    private static let _maxTokens = 4000    // 4096 for gpt-3.5-turbo and larger for gpt-4, but we use a conservative number to avoid hitting that limit

    private var _session: URLSession!
    private var _completionByTask: [Int: (String, OpenAIError?) -> Void] = [:]
    private var _tempFileURL: URL?

    private var _payload: [String: Any] = [
        "model": "gpt-3.5-turbo",
        "messages": [
            [
                "role": "system",
                "content": "You are a smart assistant that answers all user queries, questions, and statements with a single sentence."
            ]
        ]
    ]

    public init(configuration: Configuration) {
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
        }
    }

    public func send(query: String, apiKey: String, model: String, completion: @escaping (String, OpenAIError?) -> Void) {
        let requestHeader = [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json"
        ]

        _payload["model"] = model

        appendUserQueryToChatSession(query: query)

        let jsonPayload = try? JSONSerialization.data(withJSONObject: _payload)
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = requestHeader

        // If this is a background task using a file, write that file, else attach to request
        if let fileURL = _tempFileURL {
            //TODO: error handling
            try? jsonPayload?.write(to: fileURL)
        } else {
            request.httpBody = jsonPayload
        }

        // Create task
        let task = _tempFileURL == nil ? _session.dataTask(with: request) : _session.uploadTask(with: request, fromFile: _tempFileURL!)

        // Associate completion handler with this task
        _completionByTask[task.taskIdentifier] = completion

        // Begin
        task.resume()
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

    private func extractContent(from data: Data) -> (Any?, OpenAIError?, String?) {
        do {
            let jsonString = String(decoding: data, as: UTF8.self)
            if jsonString.count > 0 {
                print("[ChatGPT] Response payload: \(jsonString)")
            }
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            if let response = json as? [String: AnyObject] {
                if let errorPayload = response["error"] as? [String: AnyObject],
                   var errorMessage = errorPayload["message"] as? String {
                    // Error from OpenAI
                    if errorMessage.isEmpty {
                        // This happens sometimes, try to see if there is an error code
                        if let errorCode = errorPayload["code"] as? String,
                           !errorCode.isEmpty {
                            errorMessage = "Unable to respond. Error code: \(errorCode)"
                        } else {
                            errorMessage = "No response received. Ensure your API key is valid and try again."
                        }
                    }
                    return (json, OpenAIError.apiError(message: errorMessage), nil)
                } else if let choices = response["choices"] as? [AnyObject],
                          choices.count > 0,
                          let first = choices[0] as? [String: AnyObject],
                          let message = first["message"] as? [String: AnyObject],
                          let content = message["content"] as? String {
                    return (json, nil, content)
                }
            }
            print("[ChatGPT] Error: Unable to parse response")
        } catch {
            print("[ChatGPT] Error: Unable to deserialize response: \(error)")
        }
        return (nil, OpenAIError.responsePayloadParseError, nil)
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
                completion("", OpenAIError.clientSideNetworkError(error: error))
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
                    completion("", OpenAIError.urlAuthenticationFailed)
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
                completion("", OpenAIError.clientSideNetworkError(error: error))
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
        let (json, contentError, response) = extractContent(from: data)
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
            } else if let response = response {
                appendAIResponseToChatSession(response: response)
            }

            // Deliver response
            if let completion = self._completionByTask[dataTask.taskIdentifier] {
                completion(responseString, contentError)
                self._completionByTask.removeValue(forKey: dataTask.taskIdentifier)
            } else {
                print("[ChatGPT]: Error: No completion found for task \(dataTask.taskIdentifier)")
            }
        }
    }
}
