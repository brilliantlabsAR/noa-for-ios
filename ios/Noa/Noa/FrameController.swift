//
//  FrameController.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 12/27/23.
//
//  TODO:
//  -----
//  - Multimodal response back. Need a different type of image chunk for palettized image.
//

import AVFoundation
import CoreBluetooth
import Foundation
import UIKit

class FrameController: ObservableObject {
    // MARK: Bluetooth IDs

    static let serviceUUID = CBUUID(string: "7a230001-5475-a6a4-654c-8431f6ad49c4")
    static let txUUID = CBUUID(string: "7a230002-5475-a6a4-654c-8431f6ad49c4")
    static let rxUUID = CBUUID(string: "7a230003-5475-a6a4-654c-8431f6ad49c4")

    // MARK: Internal state

    /// Message IDs must be kept in sync with Lua scripts
    private enum MessageID: UInt8 {
        /// Start a multimodal message (containing any of text, audio, photo data)
        case multimodalStart = 0x00

        /// Text chunk. All text chunks are concatenated and terminated with `MultimodalEnd`. May
        /// safely be interleaved with other chunk types.
        case multimodalTextChunk = 0x01

        /// Audio chunk. Concatenated with other audio chunks and terminated with `MultimodalEnd`.
        /// May safely be interleaved with other chunk types.
        case multimodalAudioChunk = 0x02

        /// Photo chunk. Concatenated with other photo chunks and terminated with `MultimodalEnd`.
        /// May safely be interleaved with other chunk types.
        case multimodalPhotoChunk = 0x03

        /// Ends a multimodal message. All data attachments must have been transmitted.
        case multimodalEnd = 0x04
    }

    private let _settings: Settings
    private let _messages: ChatMessageStore
    private let _m4aWriter = M4AWriter()
    private let _ai = AIAssistant(configuration: .backgroundData)
    private var _textBuffer = Data()
    private var _audioBuffer = Data()
    private var _photoBuffer = Data()
    private var _receiveMultimodalInProgress = false

    // MARK: API

    init(settings: Settings, messages: ChatMessageStore) {
        _settings = settings
        _messages = messages
    }

    func onConnect() {
        _receiveMultimodalInProgress = false
    }

    func onDisconnect() {
        _receiveMultimodalInProgress = false
    }

    func onDataReceived(data: Data) {
        guard data.count > 0 else { return }

        if data[0] == 0x01 {
            // Binary data: a message from the Noa app
            handleMessage(data: data.subdata(in: 1..<data.count))
        } else {
            // Frame's console stdout
            log("Frame said: \(String(decoding: data, as: UTF8.self))")
        }
    }

    /// Loads a script from the iPhone's file system and writes it to the Frame's file system.
    /// It does this by sending a series of file write commands with chunks of the script encoded
    /// as string literals. For now, `[===[` and `]===]` are used, which means that scripts may not
    /// use this level of long bracket or higher.
    /// - Parameter filename: File to send.
    /// - Parameter on: Bluetooth connection to send over.
    /// - Parameter run: If true, runs this script file by executing `require('file')` after script
    /// is uploaded.
    func loadScript(named filename: String, on connection: AsyncBluetoothManager.Connection, run: Bool = false) async throws {
        let filePrefix = NSString(string: filename).deletingPathExtension   // e.g. test.lua -> test
        let script = loadLuaScript(named: filename)
        try await runCommand("f=frame.file.open('\(filename)', 'w')", on: connection)
        let maxCharsPerLine = connection.maximumWriteLength(for: .withoutResponse) - "f:write();print(nil)".count
        if maxCharsPerLine < "[===[[ ]===]".count { // worst case minimum transmission of one character
            fatalError("Bluetooth packet size is too small")
        }
        var idx = 0
        while idx < script.count {
            let (literal, numScriptChars) = encodeScriptChunkAsLiteral(script: script, from: idx, maxLength: maxCharsPerLine)
            let command = "f:write(\(literal))"
            try await runCommand(command, on: connection)
            idx += numScriptChars
            log("Uploaded: \(idx) / \(script.count) bytes of \(filename)")
        }
        try await runCommand("f:close()", on: connection)
        if run {
            connection.send(text: "require('\(filePrefix)')")
        }
    }

    // MARK: Frame commands and scripts

    private func encodeScriptChunkAsLiteral(script: String, from startIdx: Int, maxLength: Int) -> (String, Int) {
        let numCharsRemaining = script.count - startIdx
        let numCharsInChunk = min(maxLength - "[===[]===]".count, numCharsRemaining)
        let from = script.index(script.startIndex, offsetBy: startIdx)
        let to = script.index(from, offsetBy: numCharsInChunk)
        return ("[===[\(script[from..<to])]===]", numCharsInChunk)
    }

    private func runCommand(_ command: String, on connection: AsyncBluetoothManager.Connection) async throws {
        // Send command and wait for "nil" or end of stream
        connection.send(text: "\(command);print(nil)")
        for try await data in connection.receivedData {
            let response = String(decoding: data, as: UTF8.self)
            if response == "nil" {
                break
            } else {
                log("Unexpected response: \(response)")
            }
        }
    }

    private func loadLuaScript(named filename: String) -> String {
        let url = Bundle.main.url(forResource: filename, withExtension: nil)!
        let data = try? Data(contentsOf: url)
        guard let data = data else {
            fatalError("Unable to load Lua script from disk")
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Noa messages from Frame

    private func handleMessage(data: Data) {
        guard let id = MessageID(rawValue: data[0]) else {
            log("Unknown message type: \(data[0])")
            return
        }

        switch id {
        case .multimodalStart:
            _textBuffer.removeAll(keepingCapacity: true)
            _audioBuffer.removeAll(keepingCapacity: true)
            _photoBuffer.removeAll(keepingCapacity: true)
            printTypingIndicatorToChat(as: .user)
            log("Received message: MultimodalStart")

        case .multimodalTextChunk:
            if data.count > 1 {
                _textBuffer.append(data[1...])
            }
            log("Received message: MultimodalTextChunk (\(data.count) bytes)")

        case .multimodalAudioChunk:
            if data.count > 1 {
                _audioBuffer.append(data[1...])
            }
            log("Received message: MultimodalAudioChunk (\(data.count) bytes)")

        case .multimodalPhotoChunk:
            if data.count > 1 {
                _photoBuffer.append(data[1...])
            }
            log("Received message: MultimodalPhotoChunk (\(data.count) bytes)")

        case .multimodalEnd:
            submitMultimodal()
            log("Received message: MultimodalEnd")
        }
    }

    // MARK: AI

    private func submitMultimodal() {
        //TEMPORARY: construct a fake image
        _photoBuffer = Data(count: 200 * 200)
        let red: UInt8 = 0xe0
        let green: UInt8 = 0x1c
        let blue: UInt8 = 0x03
        for i in 0..<200 {
            _photoBuffer[0 * 200 + i] = red
            _photoBuffer[i * 200 + 0] = green
            _photoBuffer[i * 200 + 199] = green
            _photoBuffer[199 * 200 + i] = red
            _photoBuffer[i * 200 + i] = blue
        }

        // RGB332 -> UIImage
        var photo: UIImage? = nil
        if _photoBuffer.count == 200 * 200, // require a complete image to decode
           let pixelBuffer = CVPixelBuffer.fromRGB332(_photoBuffer, width: 200, height: 200) {
            photo = UIImage(pixelBuffer: pixelBuffer)?.resized(to: CGSize(width: 512, height: 512))
        }

        // Text
        let prompt: String? = _textBuffer.count > 0 ? String(decoding: _textBuffer, as: UTF8.self) : nil

        // 8-bit PCM -> M4A, then submit all
        if _audioBuffer.count > 0,
           let pcmBuffer = AVAudioPCMBuffer.fromMonoInt8Data(_audioBuffer, sampleRate: 8000) {
            log("Converting audio to m4a format")
            _m4aWriter.write(buffer: pcmBuffer) { [weak self] (fileData: Data?) in
                guard let self = self,
                      let fileData = fileData else {
                    self?.printErrorToChat("Unable to process audio!", as: .user)
                    return
                }
                submitMultimodal(prompt: prompt, audioFile: fileData, image: photo)
            }
        } else {
            submitMultimodal(prompt: prompt, audioFile: nil, image: photo)
        }
    }

    private func submitMultimodal(prompt: String?, audioFile: Data?, image: UIImage?) {
        _ai.send(
            prompt: prompt,
            audio: audioFile,
            image: image,
            resizeImageTo200px: false,
            imageStrength: _settings.imageStrength,
            imageGuidance: _settings.imageGuidance
        ) { [weak self] (responseImage: UIImage?, userPrompt: String, response: String, error: AIError?) in
            guard let self = self else { return }

            if let error = error {
                printErrorToChat(error.description, as: .assistant)
                return
            }

            if userPrompt.count > 0 {
                // Now that we know what user said, print it
                printToChat(userPrompt, picture: image, as: .user)
            }

            if response.count > 0 || responseImage != nil {
               printToChat(response, picture: responseImage, as: .assistant)
            }
        }
    }

    // MARK: Frame response

    private func sendResponseToFrame(text: String, image: UIImage? = nil, isError: Bool = false) {
    }

    // MARK: iOS chat window

    private func printErrorToChat(_ message: String, as participant: Participant) {
        _messages.putMessage(Message(text: message, isError: true, participant: participant))
        sendResponseToFrame(text: message, isError: true)
        log("Error printed: \(message)")
    }

    private func printTypingIndicatorToChat(as participant: Participant) {
        _messages.putMessage(Message(text: "", typingInProgress: true, participant: participant))
    }

    private func printToChat(_ text: String, picture: UIImage? = nil, as participant: Participant) {
        _messages.putMessage(Message(text: text, picture: picture, participant: participant))
        if participant != .user {
            sendResponseToFrame(text: text, image: picture, isError: false)
        }
    }
}

// MARK: Misc. helpers

fileprivate func log(_ message: String) {
    print("[FrameController] \(message)")
}