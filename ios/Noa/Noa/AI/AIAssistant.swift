//
//  AIAssistant.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/12/23.
//

import UIKit

public class AIAssistant: NSObject {
    public enum Mode {
        case assistant
        case translator
    }

    public enum NetworkConfiguration {
        case normal
        case backgroundData
        case backgroundUpload
    }

    private static let _maxTokens = 4000    // 4096 for gpt-3.5-turbo and larger for gpt-4, but we use a conservative number to avoid hitting that limit

    private class CompletionData {
        let completion: (UIImage?, String, String, AIError?) -> Void
        var receivedData = Data()

        init(completion: @escaping (UIImage?, String, String, AIError?) -> Void) {
            self.completion = completion
        }
    }

    private var _session: URLSession!
    private var _completionByTask: [Int: CompletionData] = [:]
    private var _tempFileURL: URL?

    // We maintain the message history ourselves and are unaware of server-side tool use.
    // Therefore, no images will ever appear in the conversation history and the server-side
    // version of this will differ slightly (image attachments -> higher token count).
    private var _messageHistory: [[String: Any]] = [
        [
            "role": "system",
            "content": "You are a smart assistant named Noa that answers all user queries, questions, and statements with a single sentence. You exist inside AR smart glasses the user is wearing. The camera is unfortunately VERY low quality but the user is counting on you to interpret the blurry, pixelated images. NEVER comment on image quality. Do your best with images."
        ],
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
        if _messageHistory.count > 1 {
            _messageHistory.removeSubrange(1..<_messageHistory.count)
            print("[AIAssistant] Cleared history")
        }
    }

    public func send(
        prompt: String?,
        audio: Data?,
        image: UIImage?,
        resizeImageTo200px: Bool,
        imageStrength: Float,
        imageGuidance: Int,
        completion: @escaping (UIImage?, String, String, AIError?) -> Void
    ) {
        // Get conversation history. We will append user prompt once we receive it back in the
        // response (as all or part of the prompt may be contained in the audio attachment, which
        // must be transcribed on the server).
        guard let messageHistoryPayload = try? JSONSerialization.data(withJSONObject: _messageHistory) else {
            completion(nil, "", "", AIError.internalError(message: "Internal error: Conversation history cannot be serialized"))
            return
        }

        // Create form data
        var fields: [Util.MultipartForm.Field] = [
            .init(name: "messages", data: messageHistoryPayload, isJSON: true),
            .init(name: "image_strength", text: "\(imageStrength)"),
            .init(name: "cfg_scale", text: "\(imageGuidance)")
        ]
        if let prompt = prompt {
            fields.append(.init(name: "prompt", text: prompt))
        }
        if let audio = audio {
            fields.append(.init(name: "audio", filename: "audio.m4a", contentType: "audio/m4a", data: audio))
        }
        if let image = image {
            // Stable Diffusion wants images to be multiples of 64 pixels on each side
            guard let pngImageData = getPNGData(for: image, resizeTo200px: resizeImageTo200px) else {
                completion(nil, "", "", AIError.dataFormatError(message: "Unable to crop image and convert to PNG"))
                return
            }
            fields.append(.init(name: "image", filename: "image.png", contentType: "image/png", data: pngImageData))
        }

        let form = Util.MultipartForm(fields: fields)

        // Build request
        let requestHeader = [
            "Authorization": brilliantAPIKey,
            "Content-Type": "multipart/form-data;boundary=\(form.boundary)"
        ]
        //let url = URL(string: "https://api.brilliant.xyz/noa/mm")!
        let url = URL(string: "https://api.brilliant.xyz/dev/noa/mm")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = requestHeader

        // If this is a background task using a file, write that file, else attach to request
        if let fileURL = _tempFileURL {
            //TODO: error handling
            try? form.serialize().write(to: fileURL)
        } else {
            request.httpBody = form.serialize()
        }

        // Create task
        let task = _tempFileURL == nil ? _session.dataTask(with: request) : _session.uploadTask(with: request, fromFile: _tempFileURL!)

        // Associate completion handler with this task
        _completionByTask[task.taskIdentifier] = CompletionData(completion: completion)

        // Begin
        task.resume()

    }

    /// Given a UIImage, expands it so that each side is the next integral multiple of 64 (as
    /// required by Stable Diffusion), letterboxing and centering the original content. Monocle
    /// sends images that are 640x400. Cropping them down to 640x384 produces an image
    /// that is *too small* for Stable Diffusion but bumping the size up *just* works.
    /// - Parameter for: Image to expand and obtain PNG data for.
    /// - Returns: PNG data of an expanded copy of the image or `nil` if there was an error.
    private func getPNGData(for originalImage: UIImage, resizeTo200px: Bool) -> Data? {
        // Debug: resize if necessary to simulate smaller images from Frame
        let image = resizeTo200px ? originalImage.resized(to: CGSize(width: CGFloat(200), height: CGFloat(200))) : originalImage

        // Expand each dimension to multiple of 64 that is equal or greater than current size
        let currentWidth = Int(image.size.width)
        let currentHeight = Int(image.size.height)
        let newWidth = (currentWidth + 63) & ~63
        let newHeight = (currentHeight + 63) & ~63
        let newSize = CGSize(width: CGFloat(newWidth), height: CGFloat(newHeight))
        return image.expandImageWithLetterbox(to: newSize)?.pngData()
    }

    private func appendUserQueryToChatSession(query: String) {
        // Append user prompts to maintain some sort of state. Note that we do not send back the agent responses because
        // they won't add much.
        _messageHistory.append([ "role": "user", "content": "\(query)" ])
    }

    private func appendAIResponseToChatSession(response: String) {
        _messageHistory.append([ "role": "assistant", "content": "\(response)" ])
    }

    private func printConversation() {
        // Debug log conversation history
        print("---")
        for message in _messageHistory {
            print("  role=\(message["role"]!), content=\(message["content"]!)")
        }
        print("---")
    }

    private func extractContent(from data: Data) -> (UIImage?, String?, String?, AIError?, Int) {
        struct ErrorResponse: Decodable {
            let message: String
        }

        struct MultimodalResponse: Decodable {
            let user_prompt: String
            let response: String
            let image: String
            let total_tokens: Int
        }

        // Debug print raw JSON payload
//        let jsonString = String(decoding: data, as: UTF8.self)
//        if jsonString.count > 0 {
//            print("[AIAssistant] Response payload: \(jsonString)")
//        }

        // Was there an error from server?
        if let error = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            return (nil, nil, nil, AIError.apiError(message: error.message), 0)
        }

        // We should have a valid response object
        guard let mmResponse = try? JSONDecoder().decode(MultimodalResponse.self, from: data) else {
            print("[AIAssistant] Error: Unable to deserialize response")
            return (nil, nil, nil, AIError.responsePayloadParseError, 0)
        }

        // If an image exists, try to decode it
        var image: UIImage?
        if mmResponse.image.count > 0 {
            if let base64Data = mmResponse.image.data(using: .utf8),
               let imageData = Data(base64Encoded: base64Data) {
                image = UIImage(data: imageData)
            } else {
                print("[AIAssistant] Error: Unable to decode image")
                return (nil, nil, nil, AIError.dataFormatError(message: "Unable to decode image received from server"), 0)
            }
        }

        // Extract user prompt and response
        let userPrompt = mmResponse.user_prompt.count > 0 ? mmResponse.user_prompt : nil
        let response = mmResponse.response.count > 0 ? mmResponse.response : nil

        // Return response data
        return (image, userPrompt, response, nil, mmResponse.total_tokens)
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

    private func processCompleteResponse(completionData: CompletionData) {
        let (image, userPrompt, response, contentError, totalTokensUsed) = extractContent(from: completionData.receivedData)
        let userPromptString = userPrompt ?? ""
        let responseString = response ?? "" // if response is nill, contentError will be set

        // Deliver response and append to chat session
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Append to chat session to maintain running dialog unless we've exceeded the context
            // window
            if totalTokensUsed >= Self._maxTokens {
                clearHistory()
                print("[AIAssistant] Cleared context history because total tokens used reached \(totalTokensUsed)")
            } else {
                // Append the user prompt to the message history
                if userPromptString.count > 0 {
                    appendUserQueryToChatSession(query: userPromptString)
                }

                // And also the response
                if responseString.count > 0 || image != nil {
                    appendAIResponseToChatSession(response: "\(image != nil ? "[image] " : "")\(responseString)")
                }
            }

            // Deliver response
            completionData.completion(image, userPromptString, responseString, contentError)
        }
    }
}

extension AIAssistant: URLSessionDelegate {
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        let errorMessage = error == nil ? "unknown error" : error!.localizedDescription
        print("[AIAssistant] URLSession became invalid: \(errorMessage)")

        // Deliver error for all outstanding tasks
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for (_, completionData) in self._completionByTask {
                completionData.completion(nil, "", "", AIError.clientSideNetworkError(error: error))
            }
            _completionByTask = [:]
        }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        print("[AIAssistant] URLSession finished events")
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        print("[AIAssistant] URLSession received challenge")
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            print("[AIAssistant] URLSession unable to use credential")
        }
    }
}

extension AIAssistant: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome streamTask: URLSessionStreamTask) {
        print("[AIAssistant] URLSessionDataTask became stream task")
        streamTask.resume()
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome downloadTask: URLSessionDownloadTask) {
        print("[AIAssistant] URLSessionDataTask became download task")
        downloadTask.resume()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        print("[AIAssistant] URLSessionDataTask received challenge")
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            print("[AIAssistant] URLSessionDataTask unable to use credential")

            // Deliver error
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let completionData = self._completionByTask[task.taskIdentifier] {
                    completionData.completion(nil, "", "", AIError.urlAuthenticationFailed)
                    self._completionByTask.removeValue(forKey: task.taskIdentifier)
                }
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Original request was redirected somewhere else. Create a new task for redirection.
        if let urlString = request.url?.absoluteString {
            print("[AIAssistant] URLSessionDataTask redirected to \(urlString)")
        } else {
            print("[AIAssistant] URLSessionDataTask redirected")
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
            print("[AIAssistant] URLSessionDataTask failed to complete: \(error.localizedDescription)")
        } else {
            // Success!
            print("[AIAssistant] URLSessionDataTask finished")
            if let completionData = _completionByTask[task.taskIdentifier] {
                processCompleteResponse(completionData: completionData)
                _completionByTask.removeValue(forKey: task.taskIdentifier)
            }
        }

        // If there really was no error, we should have received data, triggered the completion,
        // and removed the completion. If it's still hanging around, there must be some unknown
        // error or I am interpreting the task lifecycle incorrectly.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let completionData = self._completionByTask[task.taskIdentifier] {
                completionData.completion(nil, "", "", AIError.clientSideNetworkError(error: error))
                self._completionByTask.removeValue(forKey: task.taskIdentifier)
            }
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Assume that regardless of any error (including non-200 status code), the didCompleteWithError
        // delegate method will eventually be called and we can report the error there
        print("[AIAssistant] URLSessionDataTask received response headers")
        guard let response = response as? HTTPURLResponse else {
            print("[AIAssistant] URLSessionDataTask received unknown response type")
            return
        }
        print("[AIAssistant] URLSessionDataTask received response code \(response.statusCode)")
        completionHandler(URLSession.ResponseDisposition.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let completionData = _completionByTask[dataTask.taskIdentifier] else { return }
        completionData.receivedData.append(data)
        print("[AIAssistant] Received \(data.count) bytes")
    }
}
