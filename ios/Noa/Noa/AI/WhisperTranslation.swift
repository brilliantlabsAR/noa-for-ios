//
//  WhisperTranslation.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/24/23.
//
//  OpenAI Whisper-based translation (audio -> English text).
//
//  Background Mode Notes
//  ---------------------
//  The background configuration can successfully be launched from background mode e.g. via a
//  Bluetooth callback. Online documentation indicates a dataTask() is not allowed in background
//  mode but clearly works here. A subsequent background mode URLSession called when the first
//  completes does indeed appear to fail. Likewise, uploadTask(), which documentation states is
//  specifically intended for background mode, also fails, even when used as part of the first
//  transfer.
//
//  I do not perceive a difference using files with uploadTask().
//
//  Not sure how dataTask() with a Data buffer can work on a background queue if it is executed
//  in a separate process. But it does appear to work.
//
//  Errors appear to occur when there is some sort of a delay. For example, this log shows that
//  a ChatGPT request did not complete before another kicked off. This does not happen when the
//  app is in foreground. Somehow, multiple background requests are problematic and possibly
//  being slow-walked.
//
//    *** START 21:52:26
//    [WhisperTranslation] URLSession received challenge
//    [WhisperTranslation] URLSessionDataTask received response headers
//    [WhisperTranslation] URLSessionDataTask received response code 200
//    [WhisperTranslation] Response payload: {"text":"How fast is the CPU in my iPhone?"}
//    [WhisperTranslation] URLSessionDataTask finished
//    [AIAssistant] URLSession received challenge
//    [BluetoothManager] Received TX value!
//    [BluetoothManager] TX value UTF-8 from Monocle: f
//
//
//    *** START 21:52:41
//    [WhisperTranslation] URLSession received challenge
//    [WhisperTranslation] URLSessionDataTask received response headers
//    [WhisperTranslation] URLSessionDataTask received response code 200
//    [WhisperTranslation] Response payload: {"text":"Where do lizards sleep at night?"}
//    [WhisperTranslation] URLSessionDataTask finished
//    2023-05-24 21:52:42.937529-0700 ChatGPT for Monocle[9390:1683226] Task <107143F9-1572-4564-86F0-92A731E9BF91>.<3> finished with error [-997] Error Domain=NSURLErrorDomain Code=-997 "Lost connection to background transfer service" UserInfo={NSErrorFailingURLStringKey=https://api.openai.com/v1/chat/completions, NSErrorFailingURLKey=https://api.openai.com/v1/chat/completions, _NSURLErrorRelatedURLSessionTaskErrorKey=(
//        "BackgroundDataTask <107143F9-1572-4564-86F0-92A731E9BF91>.<3>",
//        "LocalDataTask <107143F9-1572-4564-86F0-92A731E9BF91>.<3>"
//    ), _NSURLErrorFailingURLSessionTaskErrorKey=BackgroundDataTask <107143F9-1572-4564-86F0-92A731E9BF91>.<3>, NSLocalizedDescription=Lost connection to background transfer service}
//    [AIAssistant] URLSessionDataTask failed to complete: Lost connection to background transfer service
//    *** END 21:52:42
//    [AIAssistant] URLSession received challenge
//    [AIAssistant] URLSessionDataTask received response headers
//    [AIAssistant] URLSessionDataTask received response code 200
//    [AIAssistant] Response payload: {"id":"chatcmpl-7JxFrgKumSD9JIW7p3dH5zKgAgLYX","object":"chat.completion","created":1684990363,"model":"gpt-3.5-turbo-0301","usage":{"prompt_tokens":89,"completion_tokens":24,"total_tokens":113},"choices":[{"message":{"role":"assistant","content":"A Cadbury cream egg contains approximately 150 calories, 6 grams of fat, and 20 grams of sugar."},"finish_reason":"stop","index":0}]}
//
//    *** END 21:52:47
//

import UIKit

class WhisperTranslation: NSObject {
    public enum NetworkConfiguration {
        case normal
        case backgroundData
        case backgroundUpload
    }

    public enum AudioFormat: String {
        case wav = "wav"
        case m4a = "m4a"
    }

    private var _session: URLSession!
    private var _completionByTask: [Int: (String, AIError?) -> Void] = [:]
    private var _tempFileURL: URL?

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
            let configuration = URLSessionConfiguration.background(withIdentifier: "Whisper-\(UUID().uuidString)")
            configuration.isDiscretionary = false
            configuration.shouldUseExtendedBackgroundIdleMode = true
            configuration.sessionSendsLaunchEvents = true
            configuration.allowsConstrainedNetworkAccess = true
            configuration.allowsExpensiveNetworkAccess = true
            _session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        }
    }

    public func translate(fileData: Data, format: AudioFormat, completion: @escaping (String, AIError?) -> Void) {
        let boundary = UUID().uuidString

        let url = URL(string: "https://api.brilliant.xyz/noa/translate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(brilliantAPIKey, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data;boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Form data
        var formData = Data()
        formData.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"audio\";filename=\"audio.\(format.rawValue)\"\r\n".data(using: .utf8)!)  //TODO: temperature
        formData.append("Content-Type:audio/\(format.rawValue)\r\n\r\n".data(using: .utf8)!)
        formData.append(fileData)
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

    private func extractContent(from data: Data) -> (AIError?, String?) {
        do {
            let jsonString = String(decoding: data, as: UTF8.self)
            if jsonString.count > 0 {
                print("[WhisperTranslation] Response payload: \(jsonString)")
            }
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            if let response = json as? [String: AnyObject] {
                if let errorMessage = response["message"] as? String {
                   return (AIError.apiError(message: "Error from service: \(errorMessage)"), nil)
                } else if let text = response["reply"] as? String {
                    return (nil, text)
                }
            }
            print("[WhisperTranslation] Error: Unable to parse response")
        } catch {
            print("[WhisperTranslation] Error: Unable to deserialize response: \(error)")
        }
        return (AIError.responsePayloadParseError, nil)
    }
}

extension WhisperTranslation: URLSessionDelegate {
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        let errorMessage = error == nil ? "unknown error" : error!.localizedDescription
        print("[WhisperTranslation] URLSession became invalid: \(errorMessage)")

        // Deliver error for all outstanding tasks
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for (_, completion) in self._completionByTask {
                completion("", AIError.clientSideNetworkError(error: error))
            }
            _completionByTask = [:]
        }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        print("[WhisperTranslation] URLSession finished events")
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        print("[WhisperTranslation] URLSession received challenge")
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            print("[WhisperTranslation] URLSession unable to use credential")
        }
    }
}

extension WhisperTranslation: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome streamTask: URLSessionStreamTask) {
        print("[WhisperTranslation] URLSessionDataTask became stream task")
        streamTask.resume()
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome downloadTask: URLSessionDownloadTask) {
        print("[WhisperTranslation] URLSessionDataTask became download task")
        downloadTask.resume()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        print("[WhisperTranslation] URLSessionDataTask received challenge")
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            print("[WhisperTranslation] URLSessionDataTask unable to use credential")

            // Deliver error
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let completion = self._completionByTask[task.taskIdentifier] {
                    completion("", AIError.urlAuthenticationFailed)
                    self._completionByTask.removeValue(forKey: task.taskIdentifier)
                }
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Original request was redirected somewhere else. Create a new task for redirection.
        if let urlString = request.url?.absoluteString {
            print("[WhisperTranslation] URLSessionDataTask redirected to \(urlString)")
        } else {
            print("[WhisperTranslation] URLSessionDataTask redirected")
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
            print("[WhisperTranslation] URLSessionDataTask failed to complete: \(error.localizedDescription)")
        } else {
            // Error == nil should indicate successful completion
            print("[WhisperTranslation] URLSessionDataTask finished")
        }

        // If there really was no error, we should have received data, triggered the completion,
        // and removed the completion. If it's still hanging around, there must be some unknown
        // error or I am interpreting the task lifecycle incorrectly.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let completion = self._completionByTask[task.taskIdentifier] {
                completion("", AIError.clientSideNetworkError(error: error))
                self._completionByTask.removeValue(forKey: task.taskIdentifier)
            }
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Assume that regardless of any error (including non-200 status code), the didCompleteWithError
        // delegate method will eventually be called and we can report the error there
        print("[WhisperTranslation] URLSessionDataTask received response headers")
        guard let response = response as? HTTPURLResponse else {
            print("[WhisperTranslation] URLSessionDataTask received unknown response type")
            return
        }
        print("[WhisperTranslation] URLSessionDataTask received response code \(response.statusCode)")
        completionHandler(URLSession.ResponseDisposition.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let (contentError, transcript) = self.extractContent(from: data)
        let transcriptString = transcript ?? "" // if response is nill, contentError will be set

        // Deliver response
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let completion = self._completionByTask[dataTask.taskIdentifier] {
                completion(transcriptString, contentError)
                self._completionByTask.removeValue(forKey: dataTask.taskIdentifier)
            }
        }
    }
}

