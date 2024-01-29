//
//  FrameController.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 12/27/23.
//
//  TODO:
//  -----
//  - Clear internal history whenever a Frame message arrives N minutes after last Frame or GUI
//    message.
//  - Make M4AWriter and AI assistant URL requests completely async if possible so we don't need
//    a DispatchQueue-based sender. The DispatchQueue based send is not necessarily safe if it
//    gets called again befor sending is complete (the durations between sends might be reduced).
//

import AVFoundation
import CoreBluetooth
import Foundation
import UIKit

import ColorQuantization

@MainActor
class FrameController: ObservableObject {
    // MARK: Bluetooth

    private static let k_serviceUUID = CBUUID(string: "7a230001-5475-a6a4-654c-8431f6ad49c4")
    private static let k_txUUID = CBUUID(string: "7a230002-5475-a6a4-654c-8431f6ad49c4")
    private static let k_rxUUID = CBUUID(string: "7a230003-5475-a6a4-654c-8431f6ad49c4")
    private lazy var _bluetooth = AsyncBluetoothManager(service: Self.k_serviceUUID, rxCharacteristic: Self.k_rxUUID, txCharacteristic: Self.k_txUUID)

    // MARK: Internal state

    /// Message IDs must be kept in sync with Lua scripts
    private enum MessageID: UInt8 {
        /// Start a multimodal message (containing any of text, audio, photo data)
        case multimodalStart = 0x10

        /// Text chunk. All text chunks are concatenated and terminated with `MultimodalEnd`. May
        /// safely be interleaved with other chunk types.
        case multimodalTextChunk = 0x11

        /// Audio chunk. Concatenated with other audio chunks and terminated with `MultimodalEnd`.
        /// May safely be interleaved with other chunk types. This chunk can only be sent from 
        /// Frame to phone.
        case multimodalAudioChunk = 0x12

        /// RGB332-format photo chunk. Concatenated with other photo chunks and terminated with
        /// `MultimodalEnd`. May safely be interleaved with other chunk types. May only be sent
        /// from Frame to phone.
        case multimodalImage332Chunk = 0x13

        /// Palette chunk for 4-bit color-indexed images (sent from phone  to Frame). This should
        /// be sent as a single chunk somewhere in between `MultimodalStart` and `MultimodalEnd`
        /// but before any `Image4` chunk. May ony be sent from phone to Frame.
        case multimodalPaletteChunk = 0x14

        /// Image chunk encoded as a 4-bit color-indexed linear format. Concatenated with other
        /// chunks and terminated with `MultimodalEnd`. The palette must be transmitted before the
        /// first chunk. May only be sent from phone to Frame.
        case multimodalImage4Chunk = 0x15

        /// Ends a multimodal message. All data attachments must have been transmitted.
        case multimodalEnd = 0x16
    }

    private let _settings: Settings
    private let _messages: ChatMessageStore

    private let _m4aWriter = M4AWriter()
    private let _ai = AIAssistant(configuration: .backgroundData)
    
    private var _nearbyDevices: [AsyncBluetoothManager.Peripheral] = []

    private var _textBuffer = Data()
    private var _audioBuffer = Data()
    private var _photoBuffer = Data()
    private var _receiveMultimodalInProgress = false
    private var _outgoingQueue: [Data] = []

    private let _multimodalStartMessage = Data([UInt8]([ 0x01, MessageID.multimodalStart.rawValue ] ))
    private let _multimodalEndMessage = Data([UInt8]([ 0x01, MessageID.multimodalEnd.rawValue ]))

    private var _scanTask: Task<Void, Never>!
    private var _mainTask: Task<Void, Never>!

    // MARK: API

    /// Whether a BLE connection to Frame has been established.
    @Published var isConnected = false

    /// When not connected and unpaired, the nearest unpaired candidate device to which we can try
    /// to connect.
    @Published var nearbyUnpairedDevice: CBPeripheral?

    init(settings: Settings, messages: ChatMessageStore) {
        _settings = settings
        _messages = messages
        _scanTask = Task {
            await scanForNearbyDevicesTask()
        }
        _mainTask = Task {
            await mainTask()
        }
    }

    /// Pair to device. This will also cause the Frame controller to attempt to auto-connect to the
    /// paired device.
    func pair(to peripheral: CBPeripheral) {
        // Update pairing ID. The main task's connect loop will automatically pick this up and 
        // auto-connect.
        _settings.setPairedDeviceID(peripheral.identifier)
    }

    /// Terminate Bluetooth connection, which will cause the controller to search for a new device
    /// to connect to.
    func disconnect() {
        _bluetooth.disconnect()
    }

    /// Submit a query from the iOS app directly.
    /// - Parameter query: Query string.
    public func submitQuery(query: String) {
        log("Sending iOS query to assistant: \(query)")
        submitMultimodal(prompt: query, audioFile: nil, image: nil, connection: nil)
    }

    /// Clear chat history, including ChatGPT context window.
    public func clearHistory() {
        _messages.clear()
        _ai.clearHistory()
    }

    // MARK: Tasks

    /// Scans for nearby Frame devices.
    private func scanForNearbyDevicesTask() async {
        while true {
            for await devices in _bluetooth.discoveredDevices {
                _nearbyDevices = devices
            }
        }
    }

    /// Handles the Frame connect loop and responds to events from the device.
    private func mainTask() async {
        log("Started Frame task")
        isConnected = false

        while true {
            do {
                let connection = try await connectToDevice()
                isConnected = true
                try await onConnect(on: connection)
                print("MTU size: \(connection.maximumWriteLength(for: .withoutResponse)) bytes")

                // Send scripts and issue ^D to reset and execute main.lua
                try await loadScript(named: "state.lua", on: connection)
                try await loadScript(named: "graphics.lua", on: connection)
                try await loadScript(named: "main.lua", on: connection)
                log("Starting...")
                connection.send(text: "\u{4}")
//                try await loadScript(named: "test_restore.lua", on: connection, run: true)
//                print("Starting...")

                for try await data in connection.receivedData {
                    //Util.hexDump(data)
                    onDataReceived(data: data, on: connection)
                }
            } catch let error as AsyncBluetoothManager.StreamError {
                // Disconnection falls through to loop around again
                isConnected = false
                onDisconnect()
                log("Connection lost: \(error.localizedDescription)")
            } catch is CancellationError {
                // Task was canceled, exit it entirely
                log("Task canceled!")
                break
            } catch {
                log("Unknown error: \(error.localizedDescription)")
            }
        }

        // We should never fall through to here
        isConnected = false
        log("Frame task finished")
    }

    // Finds and connects to a device. If paired, will search for that device. Otherwise, will
    // search for a nearby device and wait until the user confirms by explicitly pressing
    // "Connect". Not as complicated as it looks but the UI state management is messy. Attempts to
    // be nice by sleeping when possible and checks for cancellation between async methods that do
    // not throw. Because we don't currently ever cancel the Bluetooth task (it would be a real
    // mess to try to cancel/restart it), this could be eliminated.
    private func connectToDevice() async throws -> AsyncBluetoothManager.Connection {
        var candidateHysteresisTime = Date.distantPast

        // Keep trying until we connect
        while true {
            log("Looking for a Frame device to connect to...")
            var chosenDevice: CBPeripheral?
            while chosenDevice == nil {
                if let pairedDeviceID = _settings.pairedDeviceID {
                    // Paired case: wait for paired device to appear, auto-connect to it
                    if let targetDevice = _nearbyDevices.first(where: { $0.peripheral.identifier == pairedDeviceID })?.peripheral {
                        chosenDevice = targetDevice
                        break
                    }
                    try await Task.sleep(for: .seconds(0.5))
                } else {
                    // Unpaired case: Check whether any device is within pairing range and surface
                    // that on the nearbyUnpairedDevice property for SwiftUI view to pick up. Note
                    // that devices are already sorted in descending RSSI order so we only need to
                    // check threshold.
                    let rssiThreshold: Float = -60
                    let candidateDevice = _nearbyDevices.first(where: { $0.rssi > rssiThreshold })
                    if Date.now > candidateHysteresisTime {
                        if let candidateDevice = candidateDevice {
                            nearbyUnpairedDevice = candidateDevice.peripheral
                            // Stay in this state a moment to prevent flickering at RSSI threshold
                            candidateHysteresisTime = .now.addingTimeInterval(1)
                        } else {
                            nearbyUnpairedDevice = nil
                            candidateHysteresisTime = .distantPast
                        }
                    }
                    try await Task.sleep(for: .seconds(0.25))
                }
            }

            if let connection = await _bluetooth.connect(to: chosenDevice!) {
                // Once connected, safe to hide the device sheet
                log("Connected successfully")
                return connection
            }
            try await Task.sleep(for: .seconds(0.5))
            log("Connection to device failed! Starting over...")
        }
    }

    // MARK: Frame events

    private func onConnect(on connection: AsyncBluetoothManager.Connection) async throws {
        _receiveMultimodalInProgress = false
        _outgoingQueue.removeAll()

        // Send ^C to kill current running app. Do NOT use runCommand(). Not entirely sure why but
        // it appears to generate an additional error response and get stuck.
        connection.send(text: "\u{3}")
    }

    private func onDisconnect() {
        _receiveMultimodalInProgress = false
        _outgoingQueue.removeAll()
    }

    private func onDataReceived(data: Data, on connection: AsyncBluetoothManager.Connection) {
        guard data.count > 0 else { return }

        if data[0] == 0x01 {
            // Binary data: a message from the Noa app
            handleMessage(data: data.subdata(in: 1..<data.count), on: connection)
        } else {
            // Frame's console stdout
            log("Frame said: \(String(decoding: data, as: UTF8.self))")
        }
    }

    private func handleMessage(data: Data, on connection: AsyncBluetoothManager.Connection) {
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

        case .multimodalTextChunk:
            if data.count > 1 {
                _textBuffer.append(data[1...])
            }

        case .multimodalAudioChunk:
            if data.count > 1 {
                _audioBuffer.append(data[1...])
            }

        case .multimodalImage332Chunk:
            if data.count > 1 {
                _photoBuffer.append(data[1...])
            }

        case .multimodalEnd:
            submitMultimodal(connection: connection)

        default:
            break
        }
    }

    // MARK: AI

    private func submitMultimodal(connection: AsyncBluetoothManager.Connection) {
        // RGB332 -> UIImage
        var photo: UIImage? = nil
        if _photoBuffer.count == 200 * 200, // require a complete image to decode
           let pixelBuffer = CVPixelBuffer.fromRGB332(_photoBuffer, width: 200, height: 200, greenScaleFactor: 0.6) {
            photo = UIImage(pixelBuffer: pixelBuffer)?.rotated(by: -90)?.resized(to: CGSize(width: 512, height: 512))
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
                    self?.printErrorToChat("Unable to process audio!", as: .user, connection: connection)
                    return
                }
                submitMultimodal(prompt: prompt, audioFile: fileData, image: photo, connection: connection)
            }
        } else {
            submitMultimodal(prompt: prompt, audioFile: nil, image: photo, connection: connection)
        }
    }

    private func submitMultimodal(prompt: String?, audioFile: Data?, image: UIImage?, connection: AsyncBluetoothManager.Connection?) {
        let alreadyPrintedUser = prompt != nil && audioFile == nil
        if alreadyPrintedUser,
           let prompt = prompt {
            // Special case: if only text prompt, give immediate feedback
            printToChat(prompt, picture: image, as: .user, connection: connection)
            printTypingIndicatorToChat(as: .assistant)
        }

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
                printErrorToChat(error.description, as: .assistant, connection: connection)
                return
            }

            if userPrompt.count > 0, !alreadyPrintedUser {
                // Now that we know what user said, print it
                printToChat(userPrompt, picture: image, as: .user, connection: connection)
            }

            if response.count > 0 || responseImage != nil {
                printToChat(response, picture: responseImage, as: .assistant, connection: connection)
            }
        }
    }

    // MARK: Frame response

    private func sendResponseToFrame(on connection: AsyncBluetoothManager.Connection, text: String, image: UIImage? = nil, isError: Bool = false) {
        guard let textData = text.data(using: .utf8) else {
            log("Error: Unable to encode text response as UTF-8")
            return
        }

        _outgoingQueue.append(_multimodalStartMessage)

        let payloadSize = connection.maximumWriteLength(for: .withoutResponse)
        let maxChunkSize = payloadSize - 2  // 0x01 (data packet) and message ID bytes

        // Send text response in chunks
        var startIdx = 0
        while startIdx < textData.count {
            var message = Data([0x01, MessageID.multimodalTextChunk.rawValue])
            let endIdx = min(textData.count, startIdx + maxChunkSize)
            message.append(textData[startIdx..<endIdx])
            //Util.hexDump(message)
            _outgoingQueue.append(message)
            startIdx = endIdx
        }

        // Send palette and image in chunks. Frame cannot print text and display an image
        // simultaneously, so we prioritize text messages.
        if let image = image,
           text.isEmpty,
           let (palette, pixels) = convertImageTo4Bit(image: image) {
            // Palette chunk must go first
            var paletteMessage = Data([0x01, MessageID.multimodalPaletteChunk.rawValue])
            paletteMessage.append(palette)
            _outgoingQueue.append(paletteMessage)

            // Send image in chunks of 400 pixels (200 bytes)
            let pixelRowBytes = 200
            startIdx = 0
            while startIdx < pixels.count {
                var message = Data([0x01, MessageID.multimodalImage4Chunk.rawValue])
                let endIdx = min(pixels.count, startIdx + pixelRowBytes)
                message.append(pixels[startIdx..<endIdx])
                _outgoingQueue.append(message)
                startIdx = endIdx
            }
        }

        _outgoingQueue.append(_multimodalEndMessage)

        sendEnqueuedMessagesToFrame(on: connection)
    }

    private func convertImageTo4Bit(image: UIImage) -> (Data, Data)? {
        // Stable Diffusion images are 512x512 and we resize to 400x400 to fit within Frame's
        // 640x400 display.
        let resizedImage = image.resized(to: CGSize(width: 400, height: 400))
        guard let pixelBuffer = resizedImage.toPixelBuffer() else { return nil }

        // Quantize
        let quantized = quantizeColorsKMeans(pixelBuffer, 16, 4)
        var paletteVector = quantized.first
        var pixelVector = quantized.second

        // Make sure color 0 is always black so we don't render any color in empty border regions
        // on Frame
        setDarkestColorToBlackAndIndex0(&paletteVector, &pixelVector, 4);

        // Convert to palette and pixel data buffers
        if paletteVector.size() == 16 && pixelVector.size() > 0 {
            // Produce palette chunk, encodes as (R, G, B) byte triples
            var palette = Data(count: 16 * 3)
            for i in 0..<16 {
                palette[i * 3 + 0] = paletteVector[i].r
                palette[i * 3 + 1] = paletteVector[i].g
                palette[i * 3 + 2] = paletteVector[i].b
            }

            // Pixel data
            let pixels = Data(pixelVector)

            return (palette, pixels)
        }

        return nil
    }

    static var _cumulativeBytesSent = 0

//    private func sendEnqueuedMessagesToFrame(on connection: AsyncBluetoothManager.Connection?) {
//        let delayMS = 100//20
//        for i in 0..<_outgoingQueue.count {
//            let message = _outgoingQueue[i]
//            DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .milliseconds(i * delayMS))) { [weak self] in
//                guard let self = self, let connection = connection else { return }
//                connection.send(data: message)
//                Self._cumulativeBytesSent += message.count
//                log("Sent \(Self._cumulativeBytesSent) bytes")
//            }
//        }
//        _outgoingQueue.removeAll()
//    }

    private func sendEnqueuedMessagesToFrame(on connection: AsyncBluetoothManager.Connection?) {
        let delayMS = 50
        DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .milliseconds(delayMS))) { [weak self] in
            guard let self = self, 
                  let connection = connection,
                  let nextMessage = _outgoingQueue.first else {
                return
            }
            connection.send(data: nextMessage)
            _outgoingQueue.removeFirst()
            sendEnqueuedMessagesToFrame(on: connection)

            Self._cumulativeBytesSent += nextMessage.count
            log("\(Date.timeIntervalSinceReferenceDate) -- Sent \(Self._cumulativeBytesSent) bytes")
        }
    }

    // MARK: iOS chat window

    private func printErrorToChat(_ message: String, as participant: Participant, connection: AsyncBluetoothManager.Connection?) {
        _messages.putMessage(Message(text: message, isError: true, participant: participant))
        if let connection = connection {
            sendResponseToFrame(on: connection, text: message, isError: true)
        }
        log("Error printed: \(message)")
    }

    private func printTypingIndicatorToChat(as participant: Participant) {
        _messages.putMessage(Message(text: "", typingInProgress: true, participant: participant))
    }

    private func printToChat(_ text: String, picture: UIImage? = nil, as participant: Participant, connection: AsyncBluetoothManager.Connection?) {
        _messages.putMessage(Message(text: text, picture: picture, participant: participant))
        if participant != .user,
           let connection = connection {
            sendResponseToFrame(on: connection, text: text, image: picture, isError: false)
        }
    }

    // MARK: Frame commands and scripts

    /// Loads a script from the iPhone's file system and writes it to the Frame's file system.
    /// It does this by sending a series of file write commands with chunks of the script encoded
    /// as string literals. For now, `[===[` and `]===]` are used, which means that scripts may not
    /// use this level of long bracket or higher.
    /// - Parameter filename: File to send.
    /// - Parameter on: Bluetooth connection to send over.
    /// - Parameter run: If true, runs this script file by executing `require('file')` after script
    /// is uploaded.
    private func loadScript(named filename: String, on connection: AsyncBluetoothManager.Connection, run: Bool = false) async throws {
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

    // MARK: Debug

    private func loadTestImage() {
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
    }
}

// MARK: Misc. helpers

fileprivate func log(_ message: String) {
    print("[FrameController] \(message)")
}
