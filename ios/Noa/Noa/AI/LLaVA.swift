//
//  LLaVA.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 10/16/23.
//

import UIKit

class LLaVA: NSObject {
    public enum NetworkConfiguration {
        case normal
        case backgroundData
        case backgroundUpload
    }

    private var _session: URLSession!
    private var _completionByTask: [Int: (String, AIError?) -> Void] = [:]
    private var _responseDataByTask: [Int: Data] = [:]
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
            let configuration = URLSessionConfiguration.background(withIdentifier: "LLaVA-\(UUID().uuidString)")
            configuration.isDiscretionary = false
            configuration.shouldUseExtendedBackgroundIdleMode = true
            configuration.sessionSendsLaunchEvents = true
            configuration.allowsConstrainedNetworkAccess = true
            configuration.allowsExpensiveNetworkAccess = true
            _session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        }
    }

    public func send(jpegFileData: Data, prompt: String, completion: @escaping (String, AIError?) -> Void) {
        // Prepare URL request
        let boundary = UUID().uuidString
        let url = URL(string: "http://192.168.86.37:8080/llava")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data;boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Form data
        var formData = Data()

        // Form parameter "image_file"
        formData.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"image_file\";filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        formData.append("Content-Type:image/jpeg\r\n\r\n".data(using: .utf8)!)
        formData.append(jpegFileData)
        formData.append("\r\n".data(using: .utf8)!)

        // Form parameter "user_prompt"
        formData.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"user_prompt\"\r\n".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)
        formData.append(prompt.data(using: .utf8)!)
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

        // Associate completion handler and a buffer with this task
        _completionByTask[task.taskIdentifier] = completion
        _responseDataByTask[task.taskIdentifier] = Data()

        // Begin
        task.resume()
    }

    private func deliverImage(for taskIdentifier: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            guard let completion = _completionByTask[taskIdentifier] else {
                print("[LLaVA] Error: Lost completion data for task \(taskIdentifier)")
                _responseDataByTask.removeValue(forKey: taskIdentifier)
                return
            }

            _completionByTask.removeValue(forKey: taskIdentifier)

            guard let responseData = _responseDataByTask[taskIdentifier] else {
                print("[LLaVA] Error: Lost response data for task \(taskIdentifier)")
                return
            }

            _responseDataByTask.removeValue(forKey: taskIdentifier)

            // Extract and deliver image
            let (contentError, responseText) = self.extractContent(from: responseData)
            completion(responseText, contentError)
        }
    }

    private func extractContent(from data: Data) -> (AIError?, String) {
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            if let response = json as? [String: AnyObject] {
                // "error" field is always present in response
                if let error = response["error"] as? Bool {
                    if error {
                        // The server returned an error
                        var errorMessage = "Unknown error."
                        if response["message"] as? String != nil {
                            errorMessage = response["message"] as! String
                        }
                        return (AIError.apiError(message: errorMessage), "")
                    } else {
                        // We have a response
                        if let content = response["content"] as? String {
                            return (nil, content.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                    }
                }
            }
            print("[LLaVA] Error: Unable to parse response")
        } catch {
            print("[LLaVA] Error: Unable to deserialize response: \(error)")
        }
        return (AIError.responsePayloadParseError, "")
    }
}

extension LLaVA: URLSessionDelegate {
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        let errorMessage = error == nil ? "unknown error" : error!.localizedDescription
        print("[LLaVA] URLSession became invalid: \(errorMessage)")

        // Deliver error for all outstanding tasks
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for (_, completion) in self._completionByTask {
                completion("", AIError.clientSideNetworkError(error: error))
            }
            _completionByTask = [:]
            _responseDataByTask = [:]
        }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        print("[LLaVA] URLSession finished events")
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        print("[LLaVA] URLSession received challenge")
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            print("[LLaVA] URLSession unable to use credential")
        }
    }
}

extension LLaVA: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome streamTask: URLSessionStreamTask) {
        print("[LLaVA] URLSessionDataTask became stream task")
        streamTask.resume()
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome downloadTask: URLSessionDownloadTask) {
        print("[LLaVA] URLSessionDataTask became download task")
        downloadTask.resume()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        print("[LLaVA] URLSessionDataTask received challenge")
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            print("[LLaVA] URLSessionDataTask unable to use credential")

            // Deliver error
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let completion = self._completionByTask[task.taskIdentifier] {
                    completion("", AIError.urlAuthenticationFailed)
                    self._completionByTask.removeValue(forKey: task.taskIdentifier)
                    self._responseDataByTask.removeValue(forKey: task.taskIdentifier)
                }
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Original request was redirected somewhere else. Create a new task for redirection.
        if let urlString = request.url?.absoluteString {
            print("[LLaVA] URLSessionDataTask redirected to \(urlString)")
        } else {
            print("[LLaVA] URLSessionDataTask redirected")
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
            if let data = self._responseDataByTask[task.taskIdentifier] {
                self._responseDataByTask.removeValue(forKey: task.taskIdentifier)
                self._responseDataByTask[newTask.taskIdentifier] = data
            }
        }

        // Continue with new task
        newTask.resume()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("[LLaVA] URLSessionDataTask failed to complete: \(error.localizedDescription)")
        } else {
            // Error == nil should indicate successful completion. Process final result.
            deliverImage(for: task.taskIdentifier)
            print("[LLaVA] URLSessionDataTask finished")
        }

        // If there really was no error, we should have received data, triggered the completion,
        // and removed the completion. If it's still hanging around, there must be some unknown
        // error or I am interpreting the task lifecycle incorrectly.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let completion = self._completionByTask[task.taskIdentifier] {
                completion("", AIError.clientSideNetworkError(error: error))
                self._completionByTask.removeValue(forKey: task.taskIdentifier)
                self._responseDataByTask.removeValue(forKey: task.taskIdentifier)
            }
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Assume that regardless of any error (including non-200 status code), the didCompleteWithError
        // delegate method will eventually be called and we can report the error there
        print("[LLaVA] URLSessionDataTask received response headers")
        guard let response = response as? HTTPURLResponse else {
            print("[LLaVA] URLSessionDataTask received unknown response type")
            return
        }
        print("[LLaVA] URLSessionDataTask received response code \(response.statusCode)")
        completionHandler(URLSession.ResponseDisposition.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Responses can arrive in chunks
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if var responseData = _responseDataByTask[dataTask.taskIdentifier] {
                responseData.append(data)
                _responseDataByTask[dataTask.taskIdentifier] = responseData
            }
        }
    }
}


