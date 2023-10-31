//
//  StableDiffusion.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 8/28/23.
//

import UIKit

class StableDiffusion: NSObject {
    public enum NetworkConfiguration {
        case normal
        case backgroundData
        case backgroundUpload
    }

    private var _session: URLSession!
    private var _completionByTask: [Int: (UIImage?, String, AIError?) -> Void] = [:]
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
            let configuration = URLSessionConfiguration.background(withIdentifier: "StableDiffusion-\(UUID().uuidString)")
            configuration.isDiscretionary = false
            configuration.shouldUseExtendedBackgroundIdleMode = true
            configuration.sessionSendsLaunchEvents = true
            configuration.allowsConstrainedNetworkAccess = true
            configuration.allowsExpensiveNetworkAccess = true
            _session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        }
    }

    public func imageToImage(image: UIImage, prompt: String, model: String, strength: Float, guidance: Int, completion: @escaping (UIImage?, String, AIError?) -> Void) {
        sendImageToImageRequest(
            image: image,
            audio: nil,
            prompt: prompt,
            model: model,
            strength: strength,
            guidance: guidance,
            completion: completion
        )
    }

    public func imageToImage(image: UIImage, audio: Data, model: String, strength: Float, guidance: Int, completion: @escaping (UIImage?, String, AIError?) -> Void) {
        return sendImageToImageRequest(
            image: image,
            audio: audio,
            prompt: nil,
            model: model,
            strength: strength,
            guidance: guidance,
            completion: completion
        )
    }

    private func sendImageToImageRequest(image: UIImage, audio: Data?, prompt: String?, model: String, strength: Float, guidance: Int, completion: @escaping (UIImage?, String, AIError?) -> Void) {
        // Either audio or text prompt only
        if audio != nil && prompt != nil {
            fatalError("StableDiffusion.sendImageToImageRequest() cannot have both audio and text prompts")
        } else if audio == nil && prompt == nil {
            fatalError("StableDiffusion.sendImageToImageRequest() must have either an audio or text prompt")
        }

        // Stable Diffusion wants images to be multiples of 64 pixels on each side
        guard let pngImageData = getPNGData(for: image) else {
            DispatchQueue.main.async {
                completion(nil, "", AIError.dataFormatError(message: "Unable to crop image and convert to PNG"))
            }
            return
        }

        // Prepare URL request
        let boundary = UUID().uuidString
        let service = audio != nil ? "image_to_image_audio_prompt" : "image_to_image"
        let url = URL(string: "https://api.brilliant.xyz/noa/\(service)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(brilliantAPIKey, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data;boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Form data
        var formData = Data()

        // Form parameter "init_image"
        formData.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"init_image\";filename=\"image.png\"\r\n".data(using: .utf8)!)
        formData.append("Content-Type:image/png\r\n\r\n".data(using: .utf8)!)
        formData.append(pngImageData)
        formData.append("\r\n".data(using: .utf8)!)

        // Form parameter "model"
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"model\"\r\n".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)
        formData.append(model.data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)

        // Prompt, either audio or text
        if let prompt = prompt {
            // Form parameter "prompt"
            formData.append("--\(boundary)\r\n".data(using: .utf8)!)
            formData.append("Content-Disposition:form-data;name=\"prompt\"\r\n".data(using: .utf8)!)
            formData.append("\r\n".data(using: .utf8)!)
            formData.append(prompt.data(using: .utf8)!)
            formData.append("\r\n".data(using: .utf8)!)
        } else if let fileData = audio {
            formData.append("--\(boundary)\r\n".data(using: .utf8)!)
            formData.append("Content-Disposition:form-data;name=\"audio\";filename=\"audio.m4a\"\r\n".data(using: .utf8)!)  //TODO: temperature?
            formData.append("Content-Type:audio/m4a\r\n\r\n".data(using: .utf8)!)
            formData.append(fileData)
            formData.append("\r\n".data(using: .utf8)!)
        }

        // Form parameter "image_strength"
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"image_strength\"\r\n".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)
        formData.append("\(strength)".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)

        // Form parameter "cfg_scale"
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"cfg_scale\"\r\n".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)
        formData.append("\(guidance)".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)

        // Form parameter "samples"
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"samples\"\r\n".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)
        formData.append("1".data(using: .utf8)!)
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

        print("[StableDiffusion] Submitted image2image request with: model=\(model), strength=\(strength), guidance=\(guidance)")
    }

    /// Given a UIImage, expands it so that each side is the next integral multiple of 64 (as
    /// required by Stable Diffusion), letterboxing and centering the original content. Monocle
    /// sends images that are 640x400. Cropping them down to 640x384 produces an image
    /// that is *too small* for Stable Diffusion but bumping the size up *just* works.
    /// - Parameter for: Image to expand and obtain PNG data for.
    /// - Returns: PNG data of an expanded copy of the image or `nil` if there was an error.
    private func getPNGData(for image: UIImage) -> Data? {
        // Expand each dimension to multiple of 64 that is equal or greater than current size
        let currentWidth = Int(image.size.width)
        let currentHeight = Int(image.size.height)
        let newWidth = (currentWidth + 63) & ~63
        let newHeight = (currentHeight + 63) & ~63
        let newSize = CGSize(width: CGFloat(newWidth), height: CGFloat(newHeight))
        return image.expandImageWithLetterbox(to: newSize)?.pngData()
    }

    private func deliverImage(for taskIdentifier: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            guard let completion = _completionByTask[taskIdentifier] else {
                print("[StableDiffusion] Error: Lost completion data for task \(taskIdentifier)")
                _responseDataByTask.removeValue(forKey: taskIdentifier)
                return
            }

            _completionByTask.removeValue(forKey: taskIdentifier)

            guard let responseData = _responseDataByTask[taskIdentifier] else {
                print("[StableDiffusion] Error: Lost response data for task \(taskIdentifier)")
                return
            }

            _responseDataByTask.removeValue(forKey: taskIdentifier)

            // Extract and deliver image
            let (image, prompt, contentError) = self.extractContent(from: responseData)
            completion(image, prompt, contentError)
        }
    }

    private func extractContent(from data: Data) -> (UIImage?, String, AIError?) {
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            if let response = json as? [String: AnyObject] {
                if let errorMessage = response["message"] as? String {
                   return (nil, "", AIError.apiError(message: "Error from service: \(errorMessage)"))
                } else if let artifacts = response["artifacts"] as? [[String: AnyObject]],
                          let prompt = response["prompt"] as? String,
                       artifacts.count > 0,
                       let base64String = artifacts[0]["base64"] as? String,
                       let base64Data = base64String.data(using: .utf8),
                       let imageData = Data(base64Encoded: base64Data),
                       let image = UIImage(data: imageData) {
                    return (image, prompt, nil)
                }
            }
            print("[StableDiffusion] Error: Unable to parse response")
        } catch {
            print("[StableDiffusion] Error: Unable to deserialize response: \(error)")
        }
        return (nil, "", AIError.responsePayloadParseError)
    }
}

extension StableDiffusion: URLSessionDelegate {
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        let errorMessage = error == nil ? "unknown error" : error!.localizedDescription
        print("[StableDiffusion] URLSession became invalid: \(errorMessage)")

        // Deliver error for all outstanding tasks
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for (_, completion) in self._completionByTask {
                completion(nil, "", AIError.clientSideNetworkError(error: error))
            }
            _completionByTask = [:]
            _responseDataByTask = [:]
        }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        print("[StableDiffusion] URLSession finished events")
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        print("[StableDiffusion] URLSession received challenge")
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            print("[StableDiffusion] URLSession unable to use credential")
        }
    }
}

extension StableDiffusion: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome streamTask: URLSessionStreamTask) {
        print("[StableDiffusion] URLSessionDataTask became stream task")
        streamTask.resume()
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome downloadTask: URLSessionDownloadTask) {
        print("[StableDiffusion] URLSessionDataTask became download task")
        downloadTask.resume()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        print("[StableDiffusion] URLSessionDataTask received challenge")
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            print("[StableDiffusion] URLSessionDataTask unable to use credential")

            // Deliver error
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let completion = self._completionByTask[task.taskIdentifier] {
                    completion(nil, "", AIError.urlAuthenticationFailed)
                    self._completionByTask.removeValue(forKey: task.taskIdentifier)
                    self._responseDataByTask.removeValue(forKey: task.taskIdentifier)
                }
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Original request was redirected somewhere else. Create a new task for redirection.
        if let urlString = request.url?.absoluteString {
            print("[StableDiffusion] URLSessionDataTask redirected to \(urlString)")
        } else {
            print("[StableDiffusion] URLSessionDataTask redirected")
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
            print("[StableDiffusion] URLSessionDataTask failed to complete: \(error.localizedDescription)")
        } else {
            // Error == nil should indicate successful completion. Process final result.
            deliverImage(for: task.taskIdentifier)
            print("[StableDiffusion] URLSessionDataTask finished")
        }

        // If there really was no error, we should have received data, triggered the completion,
        // and removed the completion. If it's still hanging around, there must be some unknown
        // error or I am interpreting the task lifecycle incorrectly.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let completion = self._completionByTask[task.taskIdentifier] {
                completion(nil, "", AIError.clientSideNetworkError(error: error))
                self._completionByTask.removeValue(forKey: task.taskIdentifier)
                self._responseDataByTask.removeValue(forKey: task.taskIdentifier)
            }
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Assume that regardless of any error (including non-200 status code), the didCompleteWithError
        // delegate method will eventually be called and we can report the error there
        print("[StableDiffusion] URLSessionDataTask received response headers")
        guard let response = response as? HTTPURLResponse else {
            print("[StableDiffusion] URLSessionDataTask received unknown response type")
            return
        }
        print("[StableDiffusion] URLSessionDataTask received response code \(response.statusCode)")
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


