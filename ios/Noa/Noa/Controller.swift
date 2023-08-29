//
//  Controller.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/29/23.
//
//  Notes
//  -----
//  - There is a bug where occasionally the firmware version cannot successfully be read. What
//    appears to be happening is the "raw REPL; CTRL-B to exit" is transmitted twice, with the
//    second one being intercepted by the code awaiting the firmware version. This is probably due
//    to a race condition with the raw REPL retry timer. It *seems* to happen more frequently after
//    a firmware or FPGA update has taken place. Need to investigate this further if it becomes a
//    serious problem. Not sure why this doesn't also cause an FPGA update but if that is ever
//    observed, this should become a top priority issue to resolve.
//  - The state code is a bit much to have in one file. Future refactoring advice:
//      - Rely more on data-carrying enums. When transitioning states, pass state as a variable or
//        struct attached to the enum.
//      - Try to collapse the firmware and FPGA update stuff into a couple of states and then farm
//        the logic (including the original smaller states) into a separate object.
//  - Move Bluetooth off the main queue because FPGA updates completely saturate it. Otherwise, all
//    other communication is low bandwidth and safe to dispatch there.
//  - StreamingStringMatcher is dumb. I don't know what I was thinking there. Better just to have
//    some _serialBuffer string object that is appended to, checked, and occasionally reset. Should
//    also look into how we would deal with responses coming across as multiple transfers if we had
//    an async implementation. Probably need to observe new lines / terminating sequences like '>'.
//

import AVFoundation
import Combine
import CoreBluetooth
import CryptoKit
import Foundation
import UIKit

import NordicDFU

class Controller: ObservableObject, LoggerDelegate, DFUServiceDelegate, DFUProgressDelegate {
    // MARK: Internal State

    // Monocle characteristic IDs. Note that directionality is from Monocle's perspective (i.e., we
    // transmit to Monocle on the receive characteristic).
    private static let _serialTx = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9e")
    private static let _serialRx = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9e")
    private static let _dataTx = CBUUID(string: "e5700003-7bac-429a-b4ce-57ff900f479d")
    private static let _dataRx = CBUUID(string: "e5700002-7bac-429a-b4ce-57ff900f479d")

    // Monocle Bluetooth manager
    private let _monocleBluetooth = BluetoothManager(
        autoConnectByProximity: false,  // must not auto-connect during pairing sequence; user must have time to click Connect
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

    // DFU target Bluetooth manager
    private let _dfuBluetooth = BluetoothManager(
        autoConnectByProximity: true,   // DFU target will have different ID and so we must just auto-connect
        peripheralName: "DfuTarg",
        services: [
            CBUUID(string: "0xfe59"): "Nordic DFU"
        ],
        receiveCharacteristics: [:],    // DFUServiceConroller will handle services on its own
        transmitCharacteristics: [:]
    )

    // Nordic DFU
    private let _dfuInitiator: DFUServiceInitiator
    private var _dfuController: DFUServiceController?

    // App state
    private let _settings: Settings
    private let _messages: ChatMessageStore

    private var _subscribers = Set<AnyCancellable>()

    // Internal controller state
    private enum State: Equatable {
        case disconnected

        // Startup sequence: raw REPL, check whether firmware and FPGA updates required and perform
        // them. If DFU was performed and Monocle had to reset, we detect that case so that when we
        // get to the firmware and FPGA update phase, we can compute the correct relative
        // percentage each contributes. We pass the DFU state along in the enums themselves.
        case waitingForRawREPL(didFinishDFU: Bool)
        case waitingForFirmwareVersion(didFinishDFU: Bool)
        case waitingForFPGAVersion(didFinishDFU: Bool)

        // Continuation of startup sequence: check and update Monocle scripts
        case waitingForARGPTVersion
        case transmittingScripts(scriptTransmissionState: ScriptTransmissionState)

        // Running state: Monocle app is up and able to communicate with iOS
        case running

        // Firmware update states
        case initiateDFUAndWaitForDFUTarget(rescaleUpdatePercentage: Bool)
        case performDFU(peripheral: CBPeripheral, rescaleUpdatePercentage: Bool)

        // FPGA update states
        case initiateFPGAUpdate(maximumDataLength: Int, rescaleUpdatePercentage: Bool)
        case waitForFPGAErased(updateState: FPGAUpdateState)
        case sendNextFPGAImageChunk(updateState: FPGAUpdateState)
        case writeFPGAAndReset
    }

    private class FPGAUpdateState: Equatable {
        /// FPGA image as Base64-encoded string
        var image: String

        /// Size of a single chunk, in Base64-encoded characters
        var chunkSize: Int

        /// Total number of chunks
        var chunks: Int

        /// Next chunk to transmit
        var chunk: Int

        /// Whether we need to rescale the update percentage because of DFU
        let rescaleUpdatePercentage: Bool

        init(maximumDataLength: Int, rescaleUpdatePercentage: Bool) {
            image = Controller.loadFPGAImageAsBase64()
            chunkSize = (((maximumDataLength - 45) / 3) / 4) * 4 * 3    // update string must be 45 characters!
            chunks = image.count / chunkSize + ((image.count % chunkSize) == 0 ? 0 : 1)
            chunk = 0
            self.rescaleUpdatePercentage = rescaleUpdatePercentage
            print("[Controller] FPGA update: image=\(image.count) bytes, chunkSize=\(chunkSize), chunks=\(chunks), maximumDataLength=\(maximumDataLength)")
        }

        public var entireImageTransmitted: Bool {
            return chunk >= chunks
        }

        /// Compare whether objects are the same
        static func == (lhs: Controller.FPGAUpdateState, rhs: Controller.FPGAUpdateState) -> Bool {
            return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
        }
    }

    private class ScriptTransmissionState: Equatable {
        /// Files remaining to transmit. The first file is always transmitted next.
        var filesToTransmit: [(name: String, content: String)] = []

        init(filesToTransmit: [(name: String, content: String)]) {
            self.filesToTransmit = filesToTransmit
        }

        public func tryDequeueNextScript() -> (name: String, content: String)? {
            guard filesToTransmit.count > 0 else { return nil }
            return filesToTransmit.removeFirst()
        }

        static func == (lhs: Controller.ScriptTransmissionState, rhs: Controller.ScriptTransmissionState) -> Bool {
            return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
        }
    }

    private var _state = State.disconnected
    private var _rawREPLTimer: Timer?
    private var _matcher: Util.StreamingStringMatcher?

    private static let _firmwareURL = Bundle.main.url(forResource: "monocle-micropython-v23.219.1551", withExtension: "zip")!
    private static let _fpgaURL = Bundle.main.url(forResource: "monocle-fpga-revC", withExtension: "bin")!
    private let _requiredFirmwareVersion = "v23.219.1551"
    private let _requiredFPGAVersion = "v23.179.1006"
    private var _receivedVersionResponse = ""           // buffer for firmware and FPGA version responses
    private var _currentFirmwareVersion: String?
    private var _currentFPGAVersion: String?

    private var _audioData = Data()

    private let _m4aWriter = M4AWriter()
    private let _whisper = Whisper(configuration: .backgroundData)
    private let _chatGPT = ChatGPT(configuration: .backgroundData)
    private let _stableDiffusion = StableDiffusion(configuration: .backgroundData)

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

    /// Reports nearest Monocle within the required RSSI threshold for pairing. Only updates when unpaired otherwise value may be stale.
    @Published private(set) var nearestMonocleID: UUID?

    /// Use this to enable/disable Bluetooth
    @Published public var bluetoothEnabled = false {
        didSet {
            // Pass through to Bluetooth managers. We look for both Monocle and DfuTarg in case we
            // need to resume a firmware update that was interrupted.
            _monocleBluetooth.enabled = bluetoothEnabled
            _dfuBluetooth.enabled = bluetoothEnabled
        }
    }

    public enum UpdateState {
        case notUpdating
        case updatingFirmware
        case updatingFPGA
    }

    @Published private(set) var updateState = UpdateState.notUpdating
    @Published private(set) var updateProgressPercent: Int = 0

    public var mode = ChatGPT.Mode.assistant {
        didSet {
            if mode != oldValue {
                // Changed modes, clear context
                _chatGPT.clearHistory()
            }
        }
    }

    // MARK: Public Methods

    init(settings: Settings, messages: ChatMessageStore) {
        _settings = settings
        _messages = messages

        // Set initial state
        isMonocleConnected = _monocleBluetooth.isConnected
        pairedMonocleID = _monocleBluetooth.selectedDeviceID
        bluetoothEnabled = false

        // Nordic DFU
        let firmware = try! DFUFirmware(urlToZipFile: Self._firmwareURL)
        _dfuInitiator = DFUServiceInitiator().with(firmware: firmware)
        _dfuInitiator.delegate = self
        _dfuInitiator.logger = self
        _dfuInitiator.progressDelegate = self

        // Subscribe to changed of paired device ID setting
        _settings.$pairedDeviceID.sink(receiveValue: { [weak self] (newPairedDeviceID: UUID?) in
            guard let self = self else { return }

            if let uuid = newPairedDeviceID {
                print("[Controller] Pair to \(uuid)")
            } else {
                print("[Controller] Unpaired")
            }

            // Begin connection attempts or disconnect
            self._monocleBluetooth.selectedDeviceID = newPairedDeviceID

            // Update public state
            pairedMonocleID = newPairedDeviceID
        })
        .store(in: &_subscribers)

        // Changes in nearby list of Monocle devices
        _monocleBluetooth.discoveredDevices.sink { [weak self] (devices: [(deviceID: UUID, rssi: Float)]) in
            guard let self = self else { return }
            // If there is a Monocle that is within pairing distance, broadcast that. We use two
            // thresholds for hysteresis.
            let thresholdLow: Float = -85
            let thresholdHigh: Float = -65
            if let nearestDevice = devices.first {
                if nearestDevice.rssi > thresholdHigh {
                    nearestMonocleID = nearestDevice.deviceID
                } else if nearestDevice.rssi < thresholdLow {
                    nearestMonocleID = nil
                }
                return
            }
            nearestMonocleID = nil
        }
        .store(in: &_subscribers)

        // Connection to Monocle
        _monocleBluetooth.peripheralConnected.sink { [weak self] (deviceID: UUID) in
            guard let self = self else { return }

            print("[Controller] Monocle connected")

            // Did we arrive here as a new connection or because a DFU update was finished?
            var didFinishDFU = false
            if case .performDFU(_, _) = _state {
                didFinishDFU = true
            }

            // When Monocle is connected, stop looking for DfuTarg
            _dfuBluetooth.enabled = false
            _dfuController = nil

            // Save the paired device if we auto-connected. Currently, auto-connecting should not be
            // possible anymore.
            if self._settings.pairedDeviceID == nil {
                self._settings.setPairedDeviceID(deviceID)
            }

            // Always enter raw REPL mode
            transmitRawREPLCode()

            // Wait for confirmation that raw REPL was activated
            transitionState(to: .waitingForRawREPL(didFinishDFU: didFinishDFU))

            // Since firmware v23.181.0720, some sort of Bluetooth race condition has been exposed.
            // If the iOS app is running and then Monocle is powered on, or if Monocle is restarted
            // while the app is running, the raw REPL code is not received and Controller hangs
            // forever in the waitingForRawREPL state. Presumably, Monocle needs some time before
            // its receive characteristic is actually ready to accept data but to my knowledge, we
            // have no way to detect this using CoreBluetooth. The "solution" is to periodically
            // re-transmit the raw REPL code.
            _rawREPLTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] (timer: Timer) in
                if case .waitingForRawREPL(_) = self?._state {
                    self?.transmitRawREPLCode()
                }
            }

            // Update public state
            isMonocleConnected = true
        }.store(in: &_subscribers)

        // Monocle disconnected
        _monocleBluetooth.peripheralDisconnected.sink { [weak self] in
            guard let self = self else { return }
            print("[Controller] Monocle disconnected")

            // Are we in a DFU state?
            var isPerformingDFU = false
            switch _state {
            case .initiateDFUAndWaitForDFUTarget:
                isPerformingDFU = true
            case .performDFU(peripheral: _):
                isPerformingDFU = true
            default:
                break
            }

            if !isPerformingDFU {
                // When waiting for DFU target/performing update, a disconnect is expected and we
                // don't want to change the state. Otherwise, Monocle has disconnected and we need
                // to move to the disconnected state. Note DFU target will often connect *before*
                // we receive the Monocle disconnect event and continue to progress, hence the need
                // to check *all* DFU states.
                transitionState(to: .disconnected)
            }
        }.store(in: &_subscribers)

        // Monocle data received
        _monocleBluetooth.dataReceived.sink { [weak self] (received: (characteristic: CBUUID, value: Data)) in
            guard let self = self else { return }

            let (characteristicID, value) = received

            if characteristicID == Self._serialTx {
                handleSerialDataReceived(value)
            } else if characteristicID == Self._dataTx {
                handleDataReceived(value)
            }
        }.store(in: &_subscribers)

        // DFU target connected
        _dfuBluetooth.peripheralConnected.sink { [weak self] (deviceID: UUID) in
            guard let self = self,
                  let peripheral = _dfuBluetooth.connectedPeripheral else {
                return
            }
            print("[Controller] DFUTarget connected")

            if case let .initiateDFUAndWaitForDFUTarget(rescaleUpdatePercentage: rescaleUpdatePercentage) = _state {
                transitionState(to: .performDFU(peripheral: peripheral, rescaleUpdatePercentage: rescaleUpdatePercentage))
            } else {
                // This can occur if device is stuck in DFU mode and we bring the app up. We cannot
                // yet know whether an FPGA will follow so let's assume it won't.
                transitionState(to: .performDFU(peripheral: peripheral, rescaleUpdatePercentage: false))
            }
        }.store(in: &_subscribers)

        // DFU target disconnected (which means update succeeded, in which case device comes back
        // up as Monocle, or failed, in which case we will need to retry)
        _dfuBluetooth.peripheralDisconnected.sink { [weak self] in
            guard let self = self else { return }
            print("[Controller] DFUTarget disconnected")
            _dfuController = nil

            // DFU controller has been observed to occasionally abort for some unknown reasos,
            // which also appears to stop Bluetooth scanning. We need to bounce the Bluetooth
            // manager so it starts scanning and auto-retries DFU.
            _dfuBluetooth.enabled = false
            _dfuBluetooth.enabled = true
        }.store(in: &_subscribers)

        /// Test Dall-E
        let prompt = "Aliens celebrating 4th of July on the lake."
        let imageURL = Bundle.main.url(forResource: "Tahoe", withExtension: "jpg")!
        let imageData = try! Data(contentsOf: imageURL)
        if let picture = UIImage(data: imageData) {
            printToChat(prompt, picture: picture, as: .user)
            _stableDiffusion.imageToImage(image: picture, prompt: prompt, strength: _settings.imageStrength, guidance: _settings.imageGuidance, apiKey: _settings.stabilityAIKey) { (image: UIImage?, error: AIError?) in
                if let error = error {
                    print("[Controller] Error: \(error.description)")
                } else {
                    self.printToChat(prompt, picture: image, as: .assistant)
                }
            }
        }
    }

    /// Connect to the nearest device if one exists.
    public func connectToNearest() {
        if let nearestMonocleID = nearestMonocleID {
            // Connect to this ID. This should propagate through immediately to BluetoothManager
            // and UI.
            _settings.setPairedDeviceID(nearestMonocleID)
        }
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
        // Transition!
        _state = newState

        // Perform setup for next state
        switch newState {
        case .disconnected:
            isMonocleConnected = false
            updateState = .notUpdating
            _dfuController = nil

        case .waitingForRawREPL(didFinishDFU: let didFinishDFU):
            _matcher = nil
            _currentFirmwareVersion = nil
            _currentFPGAVersion = nil
            if !didFinishDFU {
                // Just connected, we are not currently updating
                updateState = .notUpdating
            }

        case .waitingForFirmwareVersion:
            _receivedVersionResponse = ""
            transmitFirmwareVersionCheck()

        case .waitingForFPGAVersion:
            _receivedVersionResponse = ""
            transmitFPGAVersionCheck()

        case .waitingForARGPTVersion:
            // Check Monocle script version
            transmitVersionCheck()

        case .transmittingScripts(scriptTransmissionState: let transmissionState):
            // Begin transmitting scripts
            _matcher = nil
            transmitNextScript(scriptTransmissionState: transmissionState)

        case .running:
            // Send ^D to start app
            _monocleBluetooth.send(data: Data([ 0x04 ]), on: Self._serialRx)

            // Not updating anymore
            updateState = .notUpdating

        case .initiateDFUAndWaitForDFUTarget:
            // Kick off firmware update. We will then get a disconnect event when Monocle switches
            // to DFU target mode.
            transmitInitiateFirmwareUpdateCommand()

            // Enable DFU target. We will wait until this connection actually occurs.
            _dfuBluetooth.enabled = true

            // Update the firmware...
            updateState = .updatingFirmware
            updateProgressPercent = 0

            print("[Controller] Firmware update initiated")

        case .performDFU(peripheral: let peripheral, rescaleUpdatePercentage: _):
            // We may enter this state at any time (e.g., if app starts up when Monocle is in DFU
            // state due to a previously failed update, etc.). Set the external state.
            updateState = .updatingFirmware
            updateProgressPercent = 0

            // Instantiate Nordic DFU library object that will handle the firmware update
            print("[Controller] Updating firmware...")
            _dfuController = _dfuInitiator.start(target: peripheral)

        case .initiateFPGAUpdate(maximumDataLength: let maximumDataLength, rescaleUpdatePercentage: let rescaleUpdatePercentage):
            updateState = .updatingFPGA
            updateProgressPercent = rescaleUpdatePercentage ? 50 : 0
            _matcher = nil
            let updateState = FPGAUpdateState(maximumDataLength: maximumDataLength, rescaleUpdatePercentage: rescaleUpdatePercentage)
            print("[Controller] Updating FPGA...")
            transmitFPGADisableAndErase()
            transitionState(to: .waitForFPGAErased(updateState: updateState))

        case .waitForFPGAErased(_):
            _matcher = nil

        case .sendNextFPGAImageChunk(updateState: let updateState):
            // Kick off first chunk. Subsequent chunks will be handled after each confirmation.
            _matcher = nil
            transmitNextFPGAImageChunk(updateState: updateState)

        case .writeFPGAAndReset:
            // Write to FPGA and reset device
            transmitFPGAWriteAndDeviceReset()
        }
    }

    private func handleSerialDataReceived(_ receivedValue: Data) {
        let str = String(decoding: receivedValue, as: UTF8.self)
        print("[Controller] Serial data from Monocle: \(str)")

        switch _state {
        case .waitingForRawREPL(didFinishDFU: let didFinishDFU):
            onWaitForRawREPLState(receivedString: str, didFinishDFU: didFinishDFU)

        case .waitingForFirmwareVersion(didFinishDFU: let didFinishDFU):
            onWaitForFirmwareVersionString(receivedString: str, didFinishDFU: didFinishDFU)

        case .waitingForFPGAVersion(didFinishDFU: let didFinishDFU):
            onWaitForFPGAVersionString(receivedString: str, didFinishDFU: didFinishDFU)

        case .waitingForARGPTVersion:
            onWaitForVersionString(receivedString: str)

        case .transmittingScripts(scriptTransmissionState: let transmissionState):
            onScriptTransmitted(receivedString: str, scriptTransmissionState: transmissionState)

        case .running:
            break

        case .waitForFPGAErased(updateState: let updateState):
            onFPGAErased(receivedString: str, updateState: updateState)

        case .sendNextFPGAImageChunk(updateState: let updateState):
            onFPGAImageChunkTransmitted(receivedString: str, updateState: updateState)

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

    private func onWaitForRawREPLState(receivedString str: String, didFinishDFU: Bool) {
        if _matcher == nil {
            _matcher = Util.StreamingStringMatcher(lookingFor: "raw REPL; CTRL-B to exit\r\n>")
        }

        if _matcher!.matchExists(afterAppending: str) {
            print("[Controller] Raw REPL detected")
            _matcher = nil

            // Stop transmiting the raw REPL code
            _rawREPLTimer?.invalidate()
            _rawREPLTimer = nil

            // Next, check firmware
            transitionState(to: .waitingForFirmwareVersion(didFinishDFU: didFinishDFU))
        }
    }

    private func onWaitForFirmwareVersionString(receivedString str: String, didFinishDFU: Bool) {
        _currentFirmwareVersion = nil

        // Sample version string:
        //      0000: 4f 4b 76 32 33 2e 31 38 31 2e 30 37 32 30 0d 0a  OKv23.181.0720..
        //      0010: 04 04 3e                                         ..>
        // We wait for 04 3e (e.g., in case of error, only one 04 is printed) and then parse the
        // accumulated string.
        _receivedVersionResponse += str
        if _receivedVersionResponse.contains("\u{4}>") {
            let parts = _receivedVersionResponse.components(separatedBy: .newlines)
            if !_receivedVersionResponse.contains("Error") && parts[0].count >= 3 && parts[0].starts(with: "OK") {
                _currentFirmwareVersion = String(parts[0].dropFirst(2))
            }

            print("[Controller] Firmware version: \(_currentFirmwareVersion ?? "unknown")")

            transitionState(to: .waitingForFPGAVersion(didFinishDFU: didFinishDFU))
        }
    }

    private func onWaitForFPGAVersionString(receivedString str: String, didFinishDFU: Bool) {
        _currentFPGAVersion = nil

        // Sample version string:
        //      0000: 4f 4b 62 27 76 32 33 2e 31 37 39 2e 31 30 30 36  OKb'v23.179.1006
        //      0010: 27 0d 0a 04 04 3e                                '....>
        // As before, we wait for 04 3e.
        _receivedVersionResponse += str
        if _receivedVersionResponse.contains("\u{4}>") {
            let parts = _receivedVersionResponse.components(separatedBy: .newlines)
            if !_receivedVersionResponse.contains("Error") && parts[0].count >= 3 && parts[0].starts(with: "OK") {
                let str = parts[0].replacingOccurrences(of: "b'", with: "").replacingOccurrences(of: "'", with: "") // strip out b''
                _currentFPGAVersion = String(str.dropFirst(2))  // remove 'OK'
            }

            print("[Controller] FPGA version: \(_currentFPGAVersion ?? "unknown")")

            updateMonocleOrProceedToRun(didFinishDFU: didFinishDFU)
        }
    }

    private func updateMonocleOrProceedToRun(didFinishDFU: Bool) {
        if _currentFirmwareVersion != _requiredFirmwareVersion {
            // First, kick off firmware update
            print("[Controller] Firmware update needed. Current version: \(_currentFirmwareVersion ?? "unknown")")

            // Firmware update percentage depends on whether an FPGA update will follow. If no FPGA
            // update, 0-100% of update is firmware. Otherwise, firmware accounts for 0-50%.
            let rescaleFirmwareUpdatePercentage = _currentFPGAVersion != _requiredFPGAVersion

            // Do update
            transitionState(to: .initiateDFUAndWaitForDFUTarget(rescaleUpdatePercentage: rescaleFirmwareUpdatePercentage))
        } else if _currentFPGAVersion != _requiredFPGAVersion {
            // Second, FPGA update
            print("[Controller] FPGA update needed. Current version: \(_currentFPGAVersion ?? "unknown")")

            // FPGA update percentage range depends on whether firmware (DFU) happened as part of
            // this same update cycle. If DFU update occurred, then FPGA is 50-100%. Otherwise, it
            // is 0-100%.
            let rescaleFPGAUpdatePercentage = didFinishDFU

            // Do update
            if let maximumDataLength = _monocleBluetooth.maximumDataLength, maximumDataLength > 100 {
                // Need a reasonable MTU size
                transitionState(to: .initiateFPGAUpdate(maximumDataLength: maximumDataLength, rescaleUpdatePercentage: rescaleFPGAUpdatePercentage))
            } else {
                // We don't know the MTU size or it is unreasonably small, cannot update, proceed otherwise
                let mtuSize = _monocleBluetooth.maximumDataLength == nil ? "unknown" : "\(_monocleBluetooth.maximumDataLength!)"
                print("[Controller] Error: Unable to update FPGA. MTU size: \(mtuSize)")
                transitionState(to: .waitingForARGPTVersion)
            }
        } else {
            // Proceed with uploading and running Monocle script
            transitionState(to: .waitingForARGPTVersion)
        }
    }

    private func onFPGAErased(receivedString str: String, updateState: FPGAUpdateState) {
        if _matcher == nil {
            // Annoyingly, this comes across over two transfers
            _matcher = Util.StreamingStringMatcher(lookingFor: "OK\u{4}\u{4}>")
        }

        if _matcher!.matchExists(afterAppending: str) {
            print("[Controller] FPGA successfully disabled and erased")
            transitionState(to: .sendNextFPGAImageChunk(updateState: updateState))
        }
    }

    private func transmitNextFPGAImageChunk(updateState: FPGAUpdateState) {
        print("[Controller] FPGA update: Sending chunk \(updateState.chunk)/\(updateState.chunks)")

        // Extract current chunk
        let chunkStart = updateState.image.index(updateState.image.startIndex, offsetBy: updateState.chunk * updateState.chunkSize)
        let chunkEnd = updateState.image.index(updateState.image.startIndex, offsetBy: min(updateState.image.count, (updateState.chunk + 1) * updateState.chunkSize))
        let chunkData = updateState.image[chunkStart..<chunkEnd]

        // Must be exactly 45 bytes as in FPGAUpdateState (44 bytes here, 45th byte is ^D appended to execute)
        let command = "update.Fpga.write(ubinascii.a2b_base64(b'" + chunkData + "'))"

        // Progress. If we need to rescale (because DFU update preceeded us), then we want to start
        // at 50% and end at 100%.
        let progress = min(100, 100 * updateState.chunk * updateState.chunkSize / updateState.image.count)
        let deltaProgress = progress - updateProgressPercent
        updateProgressPercent = updateState.rescaleUpdatePercentage ? (50 + (progress / 2)) : progress

        // Update state
        updateState.chunk += 1

        // Send! We will expect an OK response to be received
        if deltaProgress >= 1 {
            // Insert a delay every 1% to update display. Otherwise, the FPGA back and forth
            // completely saturates the main thread.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                self?.transmitPythonCommand(command)
            }
        } else {
            transmitPythonCommand(command)
        }
    }

    private func onFPGAImageChunkTransmitted(receivedString str: String, updateState: FPGAUpdateState) {
        if _matcher == nil {
            _matcher = Util.StreamingStringMatcher(lookingFor: "OK\u{4}\u{4}>")
        }

        if _matcher!.matchExists(afterAppending: str) {
            // This state persists and we need to keep resetting the matcher
            _matcher!.reset()

            // Transmit next chunk or finish
            if updateState.entireImageTransmitted {
                transitionState(to: .writeFPGAAndReset)
            } else {
                transmitNextFPGAImageChunk(updateState: updateState)
            }
        } else if _matcher!.charactersProcessed >= 5 {
            _matcher!.reset()

            // Probably encountered "Error" and we must retry
            updateState.chunk -= 1
            print("[Controller] FPGA update: Retrying chunk \(updateState.chunk)")
            transmitNextFPGAImageChunk(updateState: updateState)
        }
    }

    private func onWaitForVersionString(receivedString str: String) {
        // Get required script files and their version from disk
        let (filesToTransmit, expectedVersion) = loadFilesForTransmission()

        // Result of print(ARGPT_VERSION) comes across as: OK<ARGPT_VERSION>\r\n^D^D>
        // We therefore manually check for '>'. If it comes across before the string matcher has
        // seen the desired version number, we assume it has failed.
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
            // Create transmission state object containing files and proceed to transmission state
            print("[Controller] App not running on Monocle. Will transmit scripts.")
            let transmissionState = ScriptTransmissionState(filesToTransmit: filesToTransmit)
            transitionState(to: .transmittingScripts(scriptTransmissionState: transmissionState))
            return
        }

        print("[Controller] Continuing to wait for version string...")
    }

    private func onScriptTransmitted(receivedString str: String, scriptTransmissionState: ScriptTransmissionState) {
        if _matcher == nil {
            _matcher = Util.StreamingStringMatcher(lookingFor: "OK\u{4}\u{4}>")
        }

        if _matcher!.matchExists(afterAppending: str) {
            print("[Controller] Script succesfully written")
            _matcher = nil
            transmitNextScript(scriptTransmissionState: scriptTransmissionState)
        }
    }

    private func transmitRawREPLCode() {
        // ^C (kill current), ^C (again to be sure), ^A (raw REPL mode)
        _monocleBluetooth.send(data: Data([ 0x03, 0x03, 0x01 ]), on: Self._serialRx)
    }

    private func transmitFirmwareVersionCheck() {
        // Check firmware version
        transmitPythonCommand("import device;print(device.VERSION);del(device)")
    }

    private func transmitFPGAVersionCheck() {
        // Check FPGA version. We use this rather than the nicer fpga.version() interface for
        // compatibility with older firmware versions.
        transmitPythonCommand("import fpga;print(fpga.read(2,12));del(fpga)")
    }

    private func transmitInitiateFirmwareUpdateCommand() {
        // Begin a firmware update
        transmitPythonCommand("import update;update.micropython()")
    }

    private func transmitFPGADisableAndErase() {
        // Begin FPGA update by turning it off and erasing it
        transmitPythonCommand("import ubinascii,update,device,bluetooth,fpga;fpga.run(False);update.Fpga.erase()")
    }

    private func transmitFPGAWriteAndDeviceReset() {
        // Commit data to FPGA and reset device
        transmitPythonCommand("update.Fpga.write(b'done');device.reset()")
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
        _monocleBluetooth.send(data: data, on: Self._serialRx)
    }

    private func loadFilesForTransmission() -> ([(name: String, content: String)], String) {
        // Load up all the files
        let basenames = [ "states", "graphics", "main" ]
        var files: [(name: String, content: String)] = []
        for basename in basenames {
            let filename = basename + ".py"
            let contents = loadPythonScript(named: basename)
            let escapedContents = contents.replacingOccurrences(of: "\n", with: "\\n")
            files.append((name: filename, content: escapedContents))
        }
        assert(files.count >= 1 && files.count == basenames.count)

        // Compute a unique version string based on file contents
        let version = generateProgramVersionString(for: files)

        // Insert that version string into main.py
        for i in 0..<files.count {
            if files[i].name == "main.py" {
                files[i].content = "ARGPT_VERSION=\"\(version)\"\n" + files[i].content
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

    private func transmitNextScript(scriptTransmissionState: ScriptTransmissionState) {
        guard let (filename, contents) = scriptTransmissionState.tryDequeueNextScript() else {
            print("[Controller] All scripts written. Starting program...")
            transitionState(to: .running)
            return
        }

        // Construct file write commands
        guard let command = "f=open('\(filename)','w');f.write('''\(contents)''');f.close()".data(using: .utf8) else {
            print("[Controller] Internal error: Unable to construct file write comment")
            return
        }
        var data = Data()
        data.append(command)
        data.append(Data([ 0x04 ])) // ^D to execute the command

        // Send!
        _monocleBluetooth.send(data: data, on: Self._serialRx)
        print("[Controller] Sent \(filename): \(data.count) bytes")
    }

    private static func loadFPGAImageAsBase64() -> String {
        guard let data = try? Data(contentsOf: _fpgaURL) else {
            fatalError("Unable to load FPGA image from disk")
        }
        return data.base64EncodedString()
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

    // MARK: User Query Flow

    // Step 1: Voice received from Monocle and converted to M4A
    private func onVoiceReceived(voiceSample: AVAudioPCMBuffer) {
        print("[Controller] Voice received. Converting to M4A...")

        // When in translation mode, we don't perform user transcription
        printTypingIndicatorToChat(as: mode == .assistant ? .user : .translator)

        // Convert to M4A, then pass to speech transcription
        _m4aWriter.write(buffer: voiceSample) { [weak self] (fileData: Data?) in
            guard let self = self,
                  let fileData = fileData else {
                self?.printErrorToChat("Unable to process audio!", as: .user)
                return
            }
            transcribe(audioFile: fileData, mode: mode)
        }
    }

    // Step 2a: Transcribe speech to text using Whisper and send transcription UUID to Monocle
    private func transcribe(audioFile fileData: Data, mode: ChatGPT.Mode) {
        print("[Controller] Transcribing voice...")

        _whisper.transcribe(mode: mode == .assistant ? .transcription : .translation, fileData: fileData, format: .m4a, apiKey: _settings.openAIKey) { [weak self] (query: String, error: AIError?) in
            guard let self = self else { return }
            if let error = error {
                printErrorToChat(error.description, as: .user)
            } else {
                if mode == .assistant {
                    // Store query and send ID to Monocle. We need to do this because we cannot perform
                    // back-to-back network requests in background mode. Monocle will reply back with
                    // the ID, allowing us to perform a ChatGPT request.
                    let id = UUID()
                    _pendingQueryByID[id] = query
                    _monocleBluetooth.send(text: "pin:" + id.uuidString, on: Self._dataRx)
                    print("[Controller] Sent transcription ID to Monocle: \(id)")
                } else {
                    // Translation mode: No more network requests to do. Display translation.
                    printToChat(query, as: .translator)
                    print("[Controller] Translation received: \(query)")
                }
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
        let responder = mode == .assistant ? Participant.assistant : Participant.translator
        printTypingIndicatorToChat(as: responder)
        _chatGPT.send(mode: mode, query: query, apiKey: _settings.openAIKey, model: _settings.gptModel) { [weak self] (response: String, error: AIError?) in
            if let error = error {
                self?.printErrorToChat(error.description, as: responder)
            } else {
                self?.printToChat(response, as: responder)
                print("[Controller] Received response from ChatGPT for \(id): \(response)")
            }
        }
    }

    // MARK: Result Output

    private func printErrorToChat(_ message: String, as participant: Participant) {
        _messages.putMessage(Message(text: message, isError: true, participant: participant))

        // Send all error messages to Monocle
        sendTextToMonocleInChunks(text: message, isError: true)

        print("[Controller] Error printed: \(message)")
    }

    private func printTypingIndicatorToChat(as participant: Participant) {
        _messages.putMessage(Message(text: "", typingInProgress: true, participant: participant))
    }

    private func printToChat(_ text: String, picture: UIImage? = nil, as participant: Participant) {
        _messages.putMessage(Message(text: text, picture: picture, participant: participant))

        if participant != .user {
            // Send AI response to Monocle
            sendTextToMonocleInChunks(text: text, isError: false)
        }
    }

    private func sendTextToMonocleInChunks(text: String, isError: Bool) {
        guard var chunkSize = _monocleBluetooth.maximumDataLength else {
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
            _monocleBluetooth.send(text: chunk, on: Self._dataRx)
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

    // MARK: Nordic DFU Delegates

    public func logWith(_ level: LogLevel, message: String) {
        print("[Controller] DFU: \(message)")
    }

    public func dfuStateDidChange(to state: DFUState) {
        print("[Controller] DFU state changed to: \(state)")
    }

    public func dfuError(_ error: DFUError, didOccurWithMessage message: String) {
        print("[Conroller] DFU error: \(message)")
    }

    public func dfuProgressDidChange(
        for part: Int,
        outOf totalParts: Int,
        to progress: Int,
        currentSpeedBytesPerSecond: Double,
        avgSpeedBytesPerSecond: Double
    ) {
        print("[Controller] DFU progress: part=\(part)/\(totalParts), progress=\(progress)%")
        if case let .performDFU(peripheral: _, rescaleUpdatePercentage: rescaleUpdatePercentage) = _state {
            // If we need to rescale the update percentage (because an FPGA update will follow), we
            // want to go from 0-50%, so just need to divide by 2.
            updateProgressPercent = rescaleUpdatePercentage ? (progress / 2) : progress
        }
    }
}
