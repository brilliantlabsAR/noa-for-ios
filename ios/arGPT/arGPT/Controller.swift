//
//  Controller.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 5/29/23.
//
//  Notes
//  -----
//  - Perhaps StreamingStringMatcher can be replaced with something much simpler. The firmware and
//    FPGA version checkers simply accumulate string data. The reason this was not done elsewhere
//    was out of concern that this would 1) be messy and 2) not be resilient against very long,
//    "runaway" responses but (1) is simply not true and (2) is an unfounded concern. At some point
//    it would be nice to eliminate StreamingStringMatcher for simpler logic.
//

import AVFoundation
import Combine
import CoreBluetooth
import CryptoKit
import Foundation

class Controller: ObservableObject {
    // MARK: Internal State

    // Monocle characteristic IDs. Note that directionality is from Monocle's perspective (i.e., we
    // transmit to Monocle on the receive characteristic).
    private static let _serialTx = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9e")
    private static let _serialRx = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9e")
    private static let _dataTx = CBUUID(string: "e5700003-7bac-429a-b4ce-57ff900f479d")
    private static let _dataRx = CBUUID(string: "e5700002-7bac-429a-b4ce-57ff900f479d")

    private let _bluetooth = NewBluetoothManager(
        autoConnectByProximity: true,
        peripheralName: "monocle",
        services: [
            CBUUID(string: "6e400001-b5a3-f393-e0a9-e50e24dcca9e"): "Serial",
            CBUUID(string: "e5700001-7bac-429a-b4ce-57ff900f479d"): "Data"
        ],
        receiveCharacteristics: [
            Controller._serialTx: "SerialTx",
            Controller._dataTx: "DataTx",
        ],
        transmitCharacteristics: [
            Controller._serialRx: "SerialRx",
            Controller._dataRx: "DataRx"
        ]
    )

    private let _settings: Settings
    private let _messages: ChatMessageStore

    private var _subscribers = Set<AnyCancellable>()

    private enum State {
        case disconnected
        case waitingForRawREPL
        case waitingForFirmwareVersion
        case waitingForFPGAVersion
        case waitingForARGPTVersion
        case transmitingFiles
        case running
        case updatingFirmware
    }

    private var _state = State.disconnected
    private var _rawREPLTimer: Timer?
    private var _matcher: Util.StreamingStringMatcher?
    private var _filesToTransmit: [(String, String)] = []
    private var _filesVersion: String?

    private let _requiredFirmwareVersion = "v23.181.0720"
    private let _requiredFPGAVersion = "v23.181.0720"
    private var _receivedVersionResponse = ""   // buffer for firmware and FPGA version responses
    private var _firmwareVersion: String?
    private var _fpgaVersion: String?

    private var _audioData = Data()

    private let _m4aWriter = M4AWriter()
    private let _whisper = Whisper(configuration: .backgroundData)
    private let _chatGPT = ChatGPT(configuration: .backgroundData)

    private var _pendingQueryByID: [UUID: String] = [:]

    // Debug audio playback (use setupAudioSession() and playReceivedAudio() on PCM buffer decoded
    // from Monocle)
    private let _audioEngine = AVAudioEngine()
    private var _playerNode = AVAudioPlayerNode()
    private var _audioConverter: AVAudioConverter?
    private var _playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!
    private let _monocleFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 8000, channels: 1, interleaved: false)!

    // MARK: Public State

    @Published private(set) var isMonocleConnected = false
    @Published private(set) var pairedMonocleID: UUID?

    /// Use this to enable/disable Bluetooth
    @Published public var bluetoothEnabled = false {
        didSet {
            // Pass through to Bluetooth manager
            _bluetooth.enabled = bluetoothEnabled
        }
    }

    public enum UpdateState {
        case notUpdating
        case updatingFirmware
        case updatingFPGA
    }

    @Published private(set) var updateState = UpdateState.notUpdating
    @Published private(set) var updateProgressPercent: Int = 0

    // MARK: Public Methods

    init(settings: Settings, messages: ChatMessageStore) {
        _settings = settings
        _messages = messages

        // Set initial state
        isMonocleConnected = _bluetooth.isConnected
        pairedMonocleID = _bluetooth.selectedDeviceID
        bluetoothEnabled = false

        // Subscribe to changed of paired device ID setting
        _settings.$pairedDeviceID.sink(receiveValue: { [weak self] (newPairedDeviceID: UUID?) in
            guard let self = self else { return }

            if let uuid = newPairedDeviceID {
                print("[Controller] Pair to \(uuid)")
            } else {
                print("[Controller] Unpaired")
            }

            // Begin connection attempts or disconnect
            self._bluetooth.selectedDeviceID = newPairedDeviceID

            // Update public state
            pairedMonocleID = newPairedDeviceID
        })
        .store(in: &_subscribers)

        // Connection to Monocle
        _bluetooth.peripheralConnected.sink { [weak self] (deviceID: UUID) in
            guard let self = self else { return }

            print("[Controller] Monocle connected")

            if self._settings.pairedDeviceID == nil {
                // We auto-connected and should save the paired device
                self._settings.setPairedDeviceID(deviceID)
            }

            transmitRawREPLCode()

            // Wait for confirmation that raw REPL was activated
            transitionState(to: .waitingForRawREPL)

            // Since firmware v23.181.0720, some sort of Bluetooth race condition has been exposed.
            // If the iOS app is running and then Monocle is powered on, or if Monocle is restarted
            // while the app is running, the raw REPL code is not received and Controller hangs
            // forever in the waitingForRawREPL state. Presumably, Monocle needs some time before
            // its receive characteristic is actually ready to accept data but to my knowledge, we
            // have no way to detect this using CoreBluetooth. The "solution" is to periodically
            // re-transmit the raw REPL code.
            _rawREPLTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] (timer: Timer) in
                self?.transmitRawREPLCode()
            }

            // Update public state
            isMonocleConnected = true
        }.store(in: &_subscribers)

        // Monocle disconnected
        _bluetooth.peripheralDisconnected.sink { [weak self] in
            guard let self = self else { return }
            print("[Controller] Monocle disconnected")
            transitionState(to: .disconnected)
        }.store(in: &_subscribers)

        // Data received
        _bluetooth.dataReceived.sink { [weak self] (received: (characteristic: CBUUID, value: Data)) in
            guard let self = self else { return }

            let (characteristicID, value) = received

            if characteristicID == Self._serialTx {
                handleSerialDataReceived(value)
            } else if characteristicID == Self._dataTx {
                handleDataReceived(value)
            }
        }.store(in: &_subscribers)
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

    // MARK: State Transitions and Received Data Dispatch

    private func transitionState(to newState: State) {
        // Perform setup for next state
        switch newState {
        case .disconnected:
            isMonocleConnected = false
            updateState = .notUpdating

        case .waitingForRawREPL:
            _matcher = nil

        case .waitingForFirmwareVersion:
            _receivedVersionResponse = ""
            transmitFirmwareVersionCheck()

        case .waitingForFPGAVersion:
            transmitFPGAVersionCheck()

        case .waitingForARGPTVersion:
            // Load Monocle script files up and check for version
            let (filesToTransmit, version) = loadFilesForTransmission()
            _filesToTransmit = filesToTransmit
            _filesVersion = version
            transmitVersionCheck()

        case .transmitingFiles:
            // Begin transmitting scripts
            _matcher = nil
            transmitNextFile()

        case .running:
            // Send ^D to start app
            _bluetooth.send(data: Data([ 0x04 ]), on: Self._serialRx)

        case .updatingFirmware:
            // Update the firmware
            updateState = .updatingFirmware
            updateProgressPercent = 0
            print("[Controller] Updating firmware...")
        }

        // Transition!
        _state = newState
    }

    private func handleSerialDataReceived(_ receivedValue: Data) {
        let str = String(decoding: receivedValue, as: UTF8.self)
        print("[Controller] Serial data from Monocle: \(str)")

        switch _state {
        case .waitingForRawREPL:
            _firmwareVersion = nil
            _fpgaVersion = nil
            onWaitForRawREPLState(receivedString: str)

        case .waitingForFirmwareVersion:
            onWaitForFirmwareVersionString(receivedString: str)

        case .waitingForFPGAVersion:
            onWaitForFPGAVersionString(receivedString: str)

        case .waitingForARGPTVersion:
            onWaitForVersionString(receivedString: str)

        case .transmitingFiles:
            onTransmittingFilesState(receivedString: str)

        case .running:
            fallthrough

        default:
            break
        }
    }

    private func handleDataReceived(_ receivedValue: Data) {
        guard receivedValue.count >= 4,
              _state == .running else {
            return
        }

        let command = String(decoding: receivedValue[0..<4], as: UTF8.self)
        print("[Controller] Data command from Monocle: \(command)")

        onMonocleCommand(command: command, data: receivedValue[4...])
    }

    // MARK: Monocle Firmware, FPGA, and Script Transmission

    private func onWaitForRawREPLState(receivedString str: String) {
        if _matcher == nil {
            _matcher = Util.StreamingStringMatcher(lookingFor: "raw REPL; CTRL-B to exit\r\n>")
        }

        if _matcher!.matchExists(afterAppending: str) {
            print("[Controller] Raw REPL detected")
            _matcher = nil

            // Stop transmiting the raw REPL code
            _rawREPLTimer?.invalidate()
            _rawREPLTimer = nil

            // Next, check firmware version
            transitionState(to: .waitingForFirmwareVersion)
        }
    }

    private func onWaitForFirmwareVersionString(receivedString str: String) {
        var proceedToNextState = false

        // Sample version string:
        //      0000: 4f 4b 76 32 33 2e 31 38 31 2e 30 37 32 30 0d 0a  OKv23.181.0720..
        //      0010: 04 04 3e                                         ..>
        // We wait for 04 3e (e.g., in case of error, only one 04 is printed) and then parse the
        // accumulated string.
        _receivedVersionResponse += str
        if _receivedVersionResponse.contains("\u{4}>") {
            let parts = _receivedVersionResponse.components(separatedBy: .newlines)
            if _receivedVersionResponse.contains("Error") || parts[0].count <= 2 || !parts[0].starts(with: "OK") {
                _firmwareVersion = nil
            } else {
                let idxAfterOK = parts[0].index(parts[0].startIndex, offsetBy: 2)
                _firmwareVersion = String(parts[0][idxAfterOK...])
            }
            proceedToNextState = true
        } else if _receivedVersionResponse.contains("Error") {
            _firmwareVersion = nil
            proceedToNextState = true
        }

        if proceedToNextState{
            if _firmwareVersion == nil {
                print("[Controller] Error: Unable to obtain firmware version")
            } else {
                print("[Controller] Firmware version: \(_firmwareVersion!)")
            }
            transitionState(to: .waitingForFPGAVersion)
        }
    }

    private func onWaitForFPGAVersionString(receivedString str: String) {
        var proceedToNextState = false

        // Sample version string:
        //      0000: 4f 4b 62 27 76 32 33 2e 31 37 39 2e 31 30 30 36  OKb'v23.179.1006
        //      0010: 27 0d 0a 04 04 3e                                '....>
        // As before, we wait for 04 3e.
        _receivedVersionResponse += str
        if _receivedVersionResponse.contains("\u{4}>") {
            let parts = _receivedVersionResponse.components(separatedBy: .newlines)
            if _receivedVersionResponse.contains("Error") || parts[0].count <= 2 || !parts[0].starts(with: "OK") {
                _fpgaVersion = nil
            } else {
                let str = parts[0].replacingOccurrences(of: "b'", with: "").replacingOccurrences(of: "'", with: "") // strip out b''
                let idxAfterOK = str.index(str.startIndex, offsetBy: 2)
                _fpgaVersion = String(parts[0][idxAfterOK...])
            }
            proceedToNextState = true
        } else if _receivedVersionResponse.contains("Error") {
            _fpgaVersion = nil
            proceedToNextState = true
        }

        if proceedToNextState{
            if _fpgaVersion == nil {
                print("[Controller] Error: Unable to obtain FPGA version")
            } else {
                print("[Controller] FPGA version: \(_firmwareVersion!)")
            }
            updateMonocleOrProceedToRun()
        }
    }

    private func updateMonocleOrProceedToRun() {
        if _firmwareVersion != _requiredFirmwareVersion {
            // First, kick off firmware update
            print("[Controller] Firmware update needed. Current version: \(_firmwareVersion!)")
            transitionState(to: .updatingFirmware)
        } else if _fpgaVersion != _requiredFPGAVersion {
            // Second, FPGA update
            print("[Controller] FPGA update needed. Current version: \(_fpgaVersion!)")
            print("[Controller] FPGA update not yet implemented!")
            transitionState(to: .waitingForARGPTVersion)
        } else {
            // Proceed with uploading and running Monocle script
            transitionState(to: .waitingForARGPTVersion)
        }
    }

    private func onWaitForVersionString(receivedString str: String) {
        // Result of print(ARGPT_VERSION) comes across as: OK<ARGPT_VERSION>\r\n^D^D>
        // We therefore manually check for '>'. If it comes across before the string matcher has
        // seen the desired version number, we assume it has failed.
        guard let expectedVersion = _filesVersion else {
            print("[Controller] Internal error: Waiting for version state but no version set! Cannot proceed.")
            return
        }

        if _matcher == nil {
            _matcher = Util.StreamingStringMatcher(lookingFor: expectedVersion)
        }

        if _matcher!.matchExists(afterAppending: str) {
            print("[Controller] App already running on Monocle!")
            transitionState(to: .running)
            return
        }

        let expectedResponseLength = 2 + expectedVersion.count  // "OK" + version
        if str.contains(">") || _matcher!.charactersProcessed >= expectedResponseLength {
            print("[Controller] App not running on Monocle. Will transmit files.")
            transitionState(to: .transmitingFiles)
            return
        }

        print("[Controller] Continuing to wait for version string...")
    }

    private func onTransmittingFilesState(receivedString str: String) {
        if _matcher == nil {
            _matcher = Util.StreamingStringMatcher(lookingFor: "OK\u{4}\u{4}>")
        }

        if _matcher!.matchExists(afterAppending: str) {
            print("[Controller] File succesfully written")
            _matcher = nil
            if _filesToTransmit.count > 0 {
                transmitNextFile()
            } else {
                print("[Controller] All files written. Starting program...")
                transitionState(to: .running)
            }
        }
    }

    private func transmitRawREPLCode() {
        // ^C (kill current), ^C (again to be sure), ^A (raw REPL mode)
        _bluetooth.send(data: Data([ 0x03, 0x03, 0x01 ]), on: Self._serialRx)
    }

    private func transmitFirmwareVersionCheck() {
        // Check firmware version
        transmitPythonCommand("import device;print(device.VERSION);del(device)")
    }

    private func transmitFPGAVersionCheck() {
        // Check FPGA version
        transmitPythonCommand("import fpga;print(fpga.read(2,12));del(fpga)")
    }

    private func transmitVersionCheck() {
        // Check app version
        transmitPythonCommand("print(ARGPT_VERSION)")
    }

    private func transmitPythonCommand(_ command: String) {
        let command = command.data(using: .utf8)!
        var data = Data()
        data.append(command)
        data.append(Data([ 0x04 ])) // ^D to execute the command
        _bluetooth.send(data: data, on: Self._serialRx)
    }

    private func loadFilesForTransmission() -> ([(String, String)], String) {
        // Load up all the files
        let basenames = [ "states", "graphics", "main" ]
        var files: [(String, String)] = []
        for basename in basenames {
            let filename = basename + ".py"
            let contents = loadPythonScript(named: basename)
            let escapedContents = contents.replacingOccurrences(of: "\n", with: "\\n")
            files.append((filename, escapedContents))
        }
        assert(files.count >= 1 && files.count == basenames.count)

        // Compute a unique version string based on file contents
        let version = generateProgramVersionString(for: files)

        // Insert that version string into main.py
        for i in 0..<files.count {
            if files[i].0 == "main.py" {
                files[i].1 = "ARGPT_VERSION=\"\(version)\"\n" + files[i].1
            }
        }

        return (files, version)
    }

    private func loadPythonScript(named basename: String) -> String {
        let url = Bundle.main.url(forResource: basename, withExtension: "py")!
        let data = try? Data(contentsOf: url)
        guard let data = data,
              let sourceCode = String(data: data, encoding: .utf8) else {
            fatalError("Unable to load Monocle Python code from disk")
        }
        return sourceCode
    }

    private func generateProgramVersionString(for files: [(String, String)]) -> String {
        let concatenatedScripts = files.reduce(into: "") { concatenated, fileItem in
            let (filename, contents) = fileItem
            concatenated += filename
            concatenated += contents
        }
        guard let data = concatenatedScripts.data(using: .utf8) else {
            print("[Controller] Internal error: Unable to convert concatenated files into a data object")
            return "1.0"    // some default version string
        }
        let digest = SHA256.hash(data: data)
        return digest.description
    }

    private func transmitNextFile() {
        guard _filesToTransmit.count >= 1 else {
            return
        }

        let (filename, contents) = _filesToTransmit.remove(at: 0)

        // Construct file write commands
        guard let command = "f=open('\(filename)','w');f.write('''\(contents)''');f.close()".data(using: .utf8) else {
            print("[Controller] Internal error: Unable to construct file write comment")
            return
        }
        var data = Data()
        data.append(command)
        data.append(Data([ 0x04 ])) // ^D to execute the command

        // Send!
        _bluetooth.send(data: data, on: Self._serialRx)
        print("[Controller] Sent \(filename): \(data.count) bytes")
    }

    // MARK: Monocle Commands

    private func onMonocleCommand(command: String, data: Data) {
        if command.starts(with: "ast:") {
            // Delete currently stored audio and prepare to receive new audio sample over
            // multiple packets
            print("[Controller] Received audio start command")
            _audioData.removeAll(keepingCapacity: true)
        } else if command.starts(with: "dat:") {
            // Append audio data
            print("[Controller] Received audio data packet (\(data.count) bytes)")
            _audioData.append(data)
        } else if command.starts(with: "aen:") {
            // Audio finished, submit for transcription
            print("[Controller] Received complete audio buffer (\(_audioData.count) bytes)")
            if _audioData.count.isMultiple(of: 2) {
                if let pcmBuffer = AVAudioPCMBuffer.fromMonoInt8Data(_audioData, sampleRate: 8000) {
                    onVoiceReceived(voiceSample: pcmBuffer)
                } else {
                    print("[Controller] Error: Unable to convert audio data to PCM buffer")
                }
            } else {
                print("[Controller] Error: Audio buffer is not a multiple of two bytes")
            }
        } else if command.starts(with: "pon:") {
            // Transcript acknowledgment
            print("[Controller] Received pong (transcription acknowledgment)")
            let uuidStr = String(decoding: data, as: UTF8.self)
            if let uuid = UUID(uuidString: uuidStr) {
                onTranscriptionAcknowledged(id: uuid)
            }
        }
    }

    // MARK: User ChatGPT Query Flow

    // Step 1: Voice received from Monocle and converted to M4A
    private func onVoiceReceived(voiceSample: AVAudioPCMBuffer) {
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
                _bluetooth.send(text: "pin:" + id.uuidString, on: Self._dataRx)
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

    // MARK: Result Output

    private func printErrorToChat(_ message: String, as participant: Participant) {
        _messages.putMessage(Message(content: message, isError: true, participant: participant))

        // Send all error messages to Monocle
        sendTextToMonocleInChunks(text: message, isError: true)

        print("[Controller] Error printed: \(message)")
    }

    private func printTypingIndicatorToChat(as participant: Participant) {
        _messages.putMessage(Message(content: "", typingInProgress: true, participant: participant))
    }

    private func printToChat(_ message: String, as participant: Participant) {
        _messages.putMessage(Message(content: message, participant: participant))

        if !participant.isUser {
            // Send AI response to Monocle
            sendTextToMonocleInChunks(text: message, isError: false)
        }
    }

    private func sendTextToMonocleInChunks(text: String, isError: Bool) {
        guard var chunkSize = _bluetooth.maximumDataLength else {
            return
        }

        chunkSize -= 4  // make room for command identifier
        guard chunkSize > 0 else {
            print("[Controller] Internal error: Unusable write length: \(chunkSize)")
            return
        }

        // Split strings into chunks and prepend each one with the correct command
        let command = isError ? "err:" : "res:"
        var idx = 0
        while idx < text.count {
            let end = min(idx + chunkSize, text.count)
            let startIdx = text.index(text.startIndex, offsetBy: idx)
            let endIdx = text.index(text.startIndex, offsetBy: end)
            let chunk = command + text[startIdx..<endIdx]
            _bluetooth.send(text: chunk, on: Self._dataRx)
            idx = end
        }
    }

    // MARK: Debug Audio Playback

    private func setupAudioSession() {
        // Set up the app's audio session
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [ .defaultToSpeaker ])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            fatalError("Unable to set up audio session: \(error.localizedDescription)")
        }

        // Set up player
        _audioEngine.attach(_playerNode)
        _audioEngine.connect(_playerNode, to: _audioEngine.mainMixerNode, format: _playbackFormat)
        _audioEngine.prepare()
        do {
            try _audioEngine.start()
        } catch {
            print("[Controller] Error: Unable to start audio engine: \(error.localizedDescription)")
        }

        // Set up converter
        _audioConverter = AVAudioConverter(from: _monocleFormat, to: _playbackFormat)
    }

    private func playReceivedAudio(_ pcmBuffer: AVAudioPCMBuffer) {
        if let audioConverter = _audioConverter {
            var error: NSError?
            var allSamplesReceived = false
            let outputBuffer = AVAudioPCMBuffer(pcmFormat: _playbackFormat, frameCapacity: pcmBuffer.frameLength * 48/8)!
            audioConverter.reset()
            audioConverter.convert(to: outputBuffer, error: &error, withInputFrom: { (inNumPackets: AVAudioPacketCount, outError: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? in
                if allSamplesReceived {
                    outError.pointee = .noDataNow
                    return nil
                }
                allSamplesReceived = true
                outError.pointee = .haveData
                return pcmBuffer
            })

            print("\(pcmBuffer.frameLength) \(outputBuffer.frameLength)")
            print(_playbackFormat)
            print(_audioEngine.mainMixerNode.outputFormat(forBus: 0))
            print(outputBuffer.format)

            _playerNode.scheduleBuffer(outputBuffer)
            _playerNode.prepare(withFrameCount: outputBuffer.frameLength)
            _playerNode.play()
        }
    }
}
