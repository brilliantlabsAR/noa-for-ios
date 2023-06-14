//
//  Controller.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 5/29/23.
//

import AVFoundation
import Combine
import Foundation

class Controller {
    private let _settings: Settings
    private let _bluetooth: BluetoothManager
    private let _messages: ChatMessageStore

    private var _pendingQueryByID: [UUID: String] = [:]

    private let _m4aWriter = M4AWriter()
    private let _whisper = Whisper(configuration: .backgroundData)
    private let _chatGPT = ChatGPT(configuration: .backgroundData)
    private let _mockInput = MockInputGenerator()

    private var _subscribers = Set<AnyCancellable>()

    init(settings: Settings, bluetooth: BluetoothManager, messages: ChatMessageStore) {
        _settings = settings
        _bluetooth = bluetooth
        _messages = messages

        // Subscribe to changed of paired device ID setting
        _settings.$pairedDeviceID.sink(receiveValue: { [weak self] (newPairedDeviceID: UUID?) in
            guard let self = self else { return }

            if let uuid = newPairedDeviceID {
                print("[Controller] Pair to \(uuid)")
            } else {
                print("[Controller] Unpair")
            }

            // Begin connection attempts or disconnect
            self._bluetooth.selectedDeviceID = newPairedDeviceID
        })
        .store(in: &_subscribers)

        // Subscribe to change in connected device in order to detect proximal auto-connect
        _bluetooth.$connectedDeviceID.sink(receiveValue: { [weak self] (connectedDeviceID: UUID?) in
            guard let self = self else { return }

            if connectedDeviceID == nil {
                return
            }

            if self._settings.pairedDeviceID == nil {
                // We auto-connected and should save the paired device
                self._settings.setPairedDeviceID(connectedDeviceID)
            }
        })
        .store(in: &_subscribers)

        // Receive initial voice queries from Monocle, which get passed to transcription
        _bluetooth.monocleVoiceQuery.sink(receiveValue: { [weak self] (query: AVAudioPCMBuffer) in
            self?.onVoiceReceived(voiceSample: query)
        })
        .store(in: &_subscribers)

        // Receive transcription IDs back from Monocle, kicking off the ChatGPT query
        _bluetooth.monocleTranscriptionAck.sink(receiveValue: { [weak self] (id: UUID) in
            self?.onTranscriptionAcknowledged(id: id)
        })
        .store(in: &_subscribers)
    }

    /// Submit a query from the iOS app directly.
    /// - Parameter query: Query string.
    public func submitQuery(query: String) {
        let fakeID = UUID()
        print("[Controller] Sending iOS query with transcription ID \(fakeID) to ChatGPT: \(query)")
        submitQuery(query: query, transcriptionID: fakeID)
    }

    /// Clear chat history, including ChatGPT context window.
    public func clearHistory() {
        _messages.clear()
        _chatGPT.clearHistory()
    }

    // Step 1: Voice received from Monocle and converted to M4A
    private func onVoiceReceived(voiceSample: AVAudioPCMBuffer) {
        //guard let voiceSample = _mockInput.randomVoiceSample() else { return }

        print("[Controller] Voice received. Converting to M4A...")
        printTypingIndicatorToChat(as: .user)

        // Convert to M4A, then pass to speech transcription
        _m4aWriter.write(buffer: voiceSample) { [weak self] (fileData: Data?) in
            guard let fileData = fileData else {
                self?.printErrorToChat("Unable to process audio!", as: .user)
                return
            }
            self?.transcribe(audioFile: fileData)
        }
    }

    // Step 2: Transcribe speech to text using Whisper and send transcription UUID to Monocle
    private func transcribe(audioFile fileData: Data) {
        print("[Controller] Transcribing voice...")

        _whisper.transcribe(fileData: fileData, format: .m4a, apiKey: _settings.apiKey) { [weak self] (query: String, error: OpenAIError?) in
            guard let self = self else { return }
            if let error = error {
                printErrorToChat(error.description, as: .user)
            } else {
                // Store query and send ID to Monocle. We need to do this because we cannot perform
                // back-to-back network requests in background mode. Monocle will reply back with
                // the ID, allowing us to perform a ChatGPT request.
                let id = UUID()
                _pendingQueryByID[id] = query
                _bluetooth.sendToMonocle(transcriptionID: id)
                print("[Controller] Sent transcription ID to Monocle: \(id)")
            }
        }
    }

    // Step 3: Transcription UUID received, kick off ChatGPT request
    private func onTranscriptionAcknowledged(id: UUID) {
        // Fetch query
        guard let query = _pendingQueryByID.removeValue(forKey: id) else {
            return
        }

        print("[Controller] Sending transcript \(id) to ChatGPT as query: \(query)")

        submitQuery(query: query, transcriptionID: id)
    }

    private func submitQuery(query: String, transcriptionID id: UUID) {
        // User message
        printToChat(query, as: .user)

        // Send to ChatGPT
        printTypingIndicatorToChat(as: .chatGPT)
        _chatGPT.send(query: query, apiKey: _settings.apiKey, model: _settings.model) { [weak self] (response: String, error: OpenAIError?) in
            if let error = error {
                self?.printErrorToChat(error.description, as: .chatGPT)
            } else {
                self?.printToChat(response, as: .chatGPT)
                print("[Controller] Received response from ChatGPT for \(id): \(response)")
            }
        }
    }

    private func printErrorToChat(_ message: String, as participant: Participant) {
        _messages.putMessage(Message(content: message, isError: true, participant: participant))

        // Send all error messages to Monocle
        _bluetooth.sendToMonocle(message: message, isError: true)
    }

    private func printTypingIndicatorToChat(as participant: Participant) {
        _messages.putMessage(Message(content: "", typingInProgress: true, participant: participant))
    }

    private func printToChat(_ message: String, as participant: Participant) {
        _messages.putMessage(Message(content: message, participant: participant))

        if !participant.isUser {
            // Send AI response to Monocle
            _bluetooth.sendToMonocle(message: message, isError: false)
        }
    }
}
