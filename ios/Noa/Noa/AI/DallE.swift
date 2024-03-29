//
//  DallE.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 8/25/23.
//

import UIKit

class DallE: NSObject {
    public enum NetworkConfiguration {
        case normal
        case backgroundData
        case backgroundUpload
    }

    private var _session: URLSession!
    private var _completionByTask: [Int: (UIImage?, AIError?) -> Void] = [:]
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
            let configuration = URLSessionConfiguration.background(withIdentifier: "DallE-\(UUID().uuidString)")
            configuration.isDiscretionary = false
            configuration.shouldUseExtendedBackgroundIdleMode = true
            configuration.sessionSendsLaunchEvents = true
            configuration.allowsConstrainedNetworkAccess = true
            configuration.allowsExpensiveNetworkAccess = true
            _session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        }
    }

    public func renderEdit(jpegFileData: Data, maskPNGFileData: Data?, prompt: String, apiKey: String, completion: @escaping (UIImage?, AIError?) -> Void) {
        // Convert JPEG to PNG and, if no mask supplied, mask off entire image by clearing the
        // alpha channel so that the entire image is redrawn
        guard let pngImageData = convertJPEGToPNG(jpegFileData: jpegFileData, clearAlphaChannel: maskPNGFileData == nil) else {
            DispatchQueue.main.async {
                completion(nil, AIError.dataFormatError(message: "Unable to convert JPEG image to PNG data"))
            }
            return
        }

        // Prepare URL request
        let boundary = UUID().uuidString
        let url = URL(string: "https://api.openai.com/v1/images/edits")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data;boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Form data
        var formData = Data()

        // Form parameter "image" -- if mask is not supplied, alpha channel is mask (alpha=0 is
        // where image will be modified)
        formData.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"image\";filename=\"image.png\"\r\n".data(using: .utf8)!)
        formData.append("Content-Type:image/png\r\n\r\n".data(using: .utf8)!)
        formData.append(pngImageData)
        formData.append("\r\n".data(using: .utf8)!)

        // Form parameter "mask"
        if let maskPNGFileData = maskPNGFileData {
            formData.append("--\(boundary)\r\n".data(using: .utf8)!)
            formData.append("Content-Disposition:form-data;name=\"mask\";filename=\"mask.png\"\r\n".data(using: .utf8)!)
            formData.append("Content-Type:image/png\r\n\r\n".data(using: .utf8)!)
            formData.append(maskPNGFileData)
            formData.append("\r\n".data(using: .utf8)!)
        }

        // Form parameter "prompt"
        formData.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"prompt\"\r\n".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)
        formData.append(prompt.data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)

        // Form parameter "response_format"
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"response_format\"\r\n".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)
        formData.append("b64_json".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)

        // Form parameter "size"
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"size\"\r\n".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)
        formData.append("512x512".data(using: .utf8)!)
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

    private func convertJPEGToPNG(jpegFileData: Data, clearAlphaChannel: Bool) -> Data? {
        if let jpegImage = UIImage(data: jpegFileData),
           let pixelBuffer = jpegImage.toPixelBuffer() {
            if clearAlphaChannel {
                pixelBuffer.clearAlpha()
            }
            if let maskedImage = UIImage(pixelBuffer: pixelBuffer) {
                if let pngData = maskedImage.pngData() {
                    return pngData
                } else {
                    print("[DallE] Error: Failed to produce PNG encoded image")
                }
            } else {
                print("[DallE] Error: Failed to convert pixel buffer to UIImage")
            }
        } else {
            print("[DallE] Error: Unable to convert JPEG image data to a pixel buffer")
        }
        return nil
    }

    private func deliverImage(for taskIdentifier: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            guard let completion = _completionByTask[taskIdentifier] else {
                print("[DallE] Error: Lost completion data for task \(taskIdentifier)")
                _responseDataByTask.removeValue(forKey: taskIdentifier)
                return
            }

            _completionByTask.removeValue(forKey: taskIdentifier)

            guard let responseData = _responseDataByTask[taskIdentifier] else {
                print("[DallE] Error: Lost response data for task \(taskIdentifier)")
                return
            }

            _responseDataByTask.removeValue(forKey: taskIdentifier)

            // Extract and deliver image
            let (contentError, image) = self.extractContent(from: responseData)
            completion(image, contentError)
        }
    }

    private func extractContent(from data: Data) -> (AIError?, UIImage?) {
        do {
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
                    return (AIError.apiError(message: errorMessage), nil)
                } else if let dataObject = response["data"] as? [[String: String]],
                       dataObject.count > 0,
                       let base64String = dataObject[0]["b64_json"],
                       let base64Data = base64String.data(using: .utf8),
                       let imageData = Data(base64Encoded: base64Data),
                       let image = UIImage(data: imageData) {
                    return (nil, image)
                }
            }
            print("[DallE] Error: Unable to parse response")
        } catch {
            print("[DallE] Error: Unable to deserialize response: \(error)")
        }
        return (AIError.responsePayloadParseError, nil)
    }
}

extension DallE: URLSessionDelegate {
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        let errorMessage = error == nil ? "unknown error" : error!.localizedDescription
        print("[DallE] URLSession became invalid: \(errorMessage)")

        // Deliver error for all outstanding tasks
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for (_, completion) in self._completionByTask {
                completion(nil, AIError.clientSideNetworkError(error: error))
            }
            _completionByTask = [:]
            _responseDataByTask = [:]
        }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        print("[DallE] URLSession finished events")
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        print("[DallE] URLSession received challenge")
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            print("[DallE] URLSession unable to use credential")
        }
    }
}

extension DallE: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome streamTask: URLSessionStreamTask) {
        print("[DallE] URLSessionDataTask became stream task")
        streamTask.resume()
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome downloadTask: URLSessionDownloadTask) {
        print("[DallE] URLSessionDataTask became download task")
        downloadTask.resume()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        print("[DallE] URLSessionDataTask received challenge")
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            print("[DallE] URLSessionDataTask unable to use credential")

            // Deliver error
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let completion = self._completionByTask[task.taskIdentifier] {
                    completion(nil, AIError.urlAuthenticationFailed)
                    self._completionByTask.removeValue(forKey: task.taskIdentifier)
                    self._responseDataByTask.removeValue(forKey: task.taskIdentifier)
                }
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Original request was redirected somewhere else. Create a new task for redirection.
        if let urlString = request.url?.absoluteString {
            print("[DallE] URLSessionDataTask redirected to \(urlString)")
        } else {
            print("[DallE] URLSessionDataTask redirected")
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
            print("[DallE] URLSessionDataTask failed to complete: \(error.localizedDescription)")
        } else {
            // Error == nil should indicate successful completion. Process final result.
            deliverImage(for: task.taskIdentifier)
            print("[DallE] URLSessionDataTask finished")
        }

        // If there really was no error, we should have received data, triggered the completion,
        // and removed the completion. If it's still hanging around, there must be some unknown
        // error or I am interpreting the task lifecycle incorrectly.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let completion = self._completionByTask[task.taskIdentifier] {
                completion(nil, AIError.clientSideNetworkError(error: error))
                self._completionByTask.removeValue(forKey: task.taskIdentifier)
                self._responseDataByTask.removeValue(forKey: task.taskIdentifier)
            }
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Assume that regardless of any error (including non-200 status code), the didCompleteWithError
        // delegate method will eventually be called and we can report the error there
        print("[DallE] URLSessionDataTask received response headers")
        guard let response = response as? HTTPURLResponse else {
            print("[DallE] URLSessionDataTask received unknown response type")
            return
        }
        print("[DallE] URLSessionDataTask received response code \(response.statusCode)")
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


