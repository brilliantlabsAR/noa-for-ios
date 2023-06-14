//
//  SpeechToText.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 5/12/23.
//

import Speech

class SpeechToText: NSObject, SFSpeechRecognitionTaskDelegate {
    public enum SpeechToTextError: Error {
        case unauthorized
        case noRecognizer
        case recognitionFailed
    }

    private struct Request {
        public let audioBuffer: AVAudioPCMBuffer
        public let completion: (String, Error?) -> Void

        public var speechRequest: SFSpeechAudioBufferRecognitionRequest?
        public var speechTask: SFSpeechRecognitionTask?
    }

    private var _requestQueue: [Request] = []
    private var _inProgressRequest: Request?

    private var _speechRecognizer: SFSpeechRecognizer?

    public func transcribe(audioBuffer: AVAudioPCMBuffer, completion: @escaping (String, Error?) -> Void) {
        let request = Request(audioBuffer: audioBuffer, completion: completion)
        if _speechRecognizer != nil {
            _requestQueue.append(request)
            tryProcessNextRequest()
        } else {
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                guard let self = self else {
                    return
                }

                switch status {
                case .authorized:
                    self._speechRecognizer = SFSpeechRecognizer()
                    if self._speechRecognizer == nil {
                        print("[SpeechToText] Error: Unable to create a speech recognizer")
                        completion("", SpeechToTextError.noRecognizer)
                        return
                    }
                    _requestQueue.append(request)
                    tryProcessNextRequest()
                case .denied:
                    fallthrough
                case .notDetermined:
                    fallthrough
                case .restricted:
                    fallthrough
                default:
                    print("[SpeechToText] Error: Speech recognition not authorized: status = \(status)")
                    completion("", SpeechToTextError.unauthorized)
                }
            }
        }
    }

    private func tryProcessNextRequest() {
        if _inProgressRequest == nil, _requestQueue.count > 0 {
            // Create a new speech request and put it on the in-progress queue
            var request = _requestQueue.removeFirst()
            request.speechRequest = SFSpeechAudioBufferRecognitionRequest()
            request.speechTask = _speechRecognizer?.recognitionTask(with: request.speechRequest!, delegate: self)
            request.speechRequest?.append(request.audioBuffer)
            request.speechRequest?.endAudio()
            _inProgressRequest = request
        }
    }

    private func finishTask(task: SFSpeechRecognitionTask, transcription: String, error: Error?) {
        assert(_inProgressRequest != nil && _inProgressRequest?.speechTask == task)
        if let request = _inProgressRequest {
            request.completion(transcription, error)
        }

        _inProgressRequest = nil
        tryProcessNextRequest()
    }

    // MARK: - Speech Recognition, AVCaptureAudioDataOutputSampleBufferDelegate

    public func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition recognitionResult: SFSpeechRecognitionResult) {
        print("[SpeechToText] Recognized: \(recognitionResult.bestTranscription.formattedString)")
        finishTask(task: task, transcription: recognitionResult.bestTranscription.formattedString, error: nil)
    }

    public func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didHypothesizeTranscription transcription: SFTranscription) {
        // We wait a short timeout after the last partial result to impose end-of-sentence boundary
        print("[SpeechToText] Partial: \(transcription.formattedString)")
    }

    public func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {
        print("[SpeechToText] Finished \(successfully ? "successfully" : "unsuccessfully")")
        if !successfully {
            finishTask(task: task, transcription: "", error: SpeechToTextError.recognitionFailed)
        }
    }
}
