//
//  BluetoothManager.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 5/9/23.
//
//  Resources
//  ---------
//  - "The Ultimate Guide to Apple's Core Bluetooth"
//    https://punchthrough.com/core-bluetooth-basics/
//

import AVFoundation
import Combine
import CoreBluetooth

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published public var discoveredDevices: [UUID] = []
    @Published public var isConnected = false
    @Published public var monocleVoiceQuery = PassthroughSubject<AVAudioPCMBuffer, Never>() // PCM buffer containing voice query
    @Published public var monocleTranscriptionAck = PassthroughSubject<UUID, Never>()       // transcription acknowledgment, signal for iOS app to send to ChatGPT
    @Published public var connectedDeviceID: UUID?

    /// Sets the device ID to automatically connect to. This is kept separate from
    /// connectedDeviceID to avoid an infinite publishing loop from here -> Settings -> here when
    /// auto-connecting by proximity.
    public var selectedDeviceID: UUID? {
        didSet {
            if let connectedPeripheral = _connectedPeripheral {
                // We have a connected peripheral. See if desired device ID changed and if so,
                // disconnect.
                if selectedDeviceID != connectedPeripheral.identifier {
                    _manager.cancelPeripheralConnection(connectedPeripheral)
                    connectedDeviceID = nil
                }
            }
        }
    }

    private let _monoclePythonScript: Data

    private let _monocleSerialServiceUUID = CBUUID(string: "6e400001-b5a3-f393-e0a9-e50e24dcca9e")
    private let _serialRxCharacteristicUUID = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9e")
    private let _serialTxCharacteristicUUID = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9e")
    private let _monocleDataServiceUUID = CBUUID(string: "e5700001-7bac-429a-b4ce-57ff900f479d")
    private let _dataRxCharacteristicUUID = CBUUID(string: "e5700002-7bac-429a-b4ce-57ff900f479d")
    private let _dataTxCharacteristicUUID = CBUUID(string: "e5700003-7bac-429a-b4ce-57ff900f479d")
    private let _monocleName = "monocle"
    private let _rssiAutoConnectThreshold: Float = -70

    private lazy var _manager: CBCentralManager = {
        return CBCentralManager(delegate: self, queue: .main)
    }()

    private let _allowAutoConnectByProximity: Bool

    private var _discoveredPeripherals: [(peripheral: CBPeripheral, timeout: TimeInterval)] = []
    private var _discoveryTimer: Timer?

    private var _connectedPeripheral: CBPeripheral? {
        didSet {
            isConnected = _connectedPeripheral != nil

            // If we auto-connected and selectedDeviceID was nil, set the selected ID
            if selectedDeviceID == nil, let connectedPeripheral = _connectedPeripheral {
                selectedDeviceID = connectedPeripheral.identifier
            }
        }
    }

    private var _serialTx: CBCharacteristic?
    private var _serialRx: CBCharacteristic?
    private var _dataRx: CBCharacteristic?
    private var _dataTx: CBCharacteristic?

    private var _waitingForMicroPython = true

    private var _audioData = Data()

    public init(monoclePythonScript: String, autoConnectByProximity: Bool) {
        _monoclePythonScript = monoclePythonScript.data(using: .utf8)!
        _allowAutoConnectByProximity = autoConnectByProximity

        super.init()

        // Ensure manager is instantiated; all logic will then be driven by centralManagerDidUpdateState()
        _ = _manager
    }

    public func sendToMonocle(transcriptionID: UUID) {
        guard let rx = _dataRx,
              let connectedPeripheral = _connectedPeripheral else {
            return
        }

        // Transmit on RX
        let transcriptionIDPacket = "pin:" + transcriptionID.uuidString
        if let data = transcriptionIDPacket.data(using: .utf8) {
            writeData(data, for: rx, peripheral: connectedPeripheral)
        }
    }

    public func sendToMonocle(message: String, isError: Bool) {
        guard let rx = _dataRx,
              let connectedPeripheral = _connectedPeripheral else {
            return
        }

        let messagePacket = (isError ? "err:" : "res:") + message
        if let data = messagePacket.data(using: .utf8) {
            writeData(data, for: rx, peripheral: connectedPeripheral)
        }
    }

    private func startScan() {
        _manager.scanForPeripherals(withServices: [ _monocleSerialServiceUUID, _monocleDataServiceUUID ], options: [ CBCentralManagerScanOptionAllowDuplicatesKey: true ])
        print("[BluetoothManager] Scan initiated")

        // Create a timer to update discoved peripheral list
        _discoveryTimer?.invalidate()
        _discoveryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] (timer: Timer) in
            self?.updateDiscoveredPeripherals()
        }
    }

    private func connectPeripheral(_ peripheral: CBPeripheral) {
        precondition(_connectedPeripheral == nil)
        _manager.connect(peripheral)
        _connectedPeripheral = peripheral
        _serialTx = nil
        _serialRx = nil
        _dataTx = nil
        _dataRx = nil
        _waitingForMicroPython = true

        // No need to continue scanning
        _manager.stopScan()

        // Broadcast
        connectedDeviceID = peripheral.identifier
    }

    private func forgetPeripheral() {
        _connectedPeripheral?.delegate = nil
        _connectedPeripheral = nil
        _serialTx = nil
        _serialRx = nil
        _dataTx = nil
        _dataRx = nil
        _waitingForMicroPython = true
        connectedDeviceID = nil
    }

    private func forgetCharacteristics() {
        _serialTx = nil
        _serialRx = nil
        _dataTx = nil
        _dataRx = nil
    }

    private func updateDiscoveredPeripherals(with peripheral: CBPeripheral? = nil) {
        let numPeripheralsBefore = _discoveredPeripherals.count

        // Delete anything that has timed out
        let now = Date.timeIntervalSinceReferenceDate
        _discoveredPeripherals.removeAll { $0.timeout >= now }

        // If we are adding a peripheral, remove dupes first
        if let peripheral = peripheral {
            _discoveredPeripherals.removeAll { $0.peripheral.isEqual(peripheral) }
            _discoveredPeripherals.append((peripheral: peripheral, timeout: now + 10))  // timeout after 10 seconds
        }

        // Update device list and log it
        if _discoveredPeripherals.count > 0 && (numPeripheralsBefore != _discoveredPeripherals.count || peripheral != nil) {
            print("[BluetoothManager] Discovered peripherals:")
            for (peripheral, _) in _discoveredPeripherals {
                print("[BluetoothManager]   name=\(peripheral.name ?? "<no name>") id=\(peripheral.identifier)")
            }
            discoveredDevices = _discoveredPeripherals.map { $0.peripheral.identifier }
        }
    }

    private func printServices() {
        guard let peripheral = _connectedPeripheral else { return }

        if let services = peripheral.services {
            print("[BluetoothManager] Listing services for peripheral: name=\(peripheral.name ?? ""), UUID=\(peripheral.identifier)")
            for service in services {
                print("[BluetoothManager]   Service: UUID=\(service.uuid), description=\(service.description)")
            }
        } else {
            print("[BluetoothManager] No services for peripheral UUID=\(peripheral.identifier)")
        }
    }

    private func discoverCharacteristics() {
        guard let peripheral = _connectedPeripheral,
              let services = peripheral.services else {
            return
        }

        forgetCharacteristics()

        for service in services {
            peripheral.discoverCharacteristics([ _serialRxCharacteristicUUID, _serialTxCharacteristicUUID, _dataRxCharacteristicUUID, _dataTxCharacteristicUUID ], for: service)
        }
    }

    private func printCharacteristics(of service: CBService) {
        if let characteristics = service.characteristics {
            print("[BluetoothManager] Listing characteristics for service: description=\(service.description), UUID=\(service.uuid)")
            for characteristic in characteristics {
                print("[BluetoothManager]   Characteristic: description=\(characteristic.description), UUID=\(characteristic.uuid)")
            }
        } else {
            print("[BluetoothManager] No characteristics for service UUID=\(service.uuid)")
        }
    }

    private func saveCharacteristics(of service: CBService) {
        forgetCharacteristics()

        guard let peripheral = _connectedPeripheral else { return }

        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                if characteristic.uuid == _serialTxCharacteristicUUID {
                    _serialTx = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)    // receive notifications from Monocle
                    print("[BluetoothManager] Obtained SerialTx")
                }

                if characteristic.uuid == _serialRxCharacteristicUUID {
                    _serialRx = characteristic
                    print("[BluetoothManager] Obtained SerialRx")

                    // Once we have serial RX, transmit program to Monocle
                    transmitMonocleProgram()
                }

                if characteristic.uuid == _dataTxCharacteristicUUID {
                    _dataTx = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                    print("[BluetoothManager] Obtained DataTx")
                }

                if characteristic.uuid == _dataRxCharacteristicUUID {
                    _dataRx = characteristic
                    print("[BluetoothManager] Obtained DataRx")
                }
            }
        }
    }

    // MARK: MicroPython script transmission

    private func transmitMonocleProgram() {
        guard let connectedPeripheral = _connectedPeripheral,
              let serialRx = _serialRx else {
            return
        }

        print("[BluetoothManager] Write length = \(connectedPeripheral.maximumWriteValueLength(for: .withoutResponse))")

        let rawREPLCommandCode = Data([ 0x03, 0x03, 0x01 ]) // ^C (kill current), ^C (again to be sure), ^A (raw REPL mode)
        let endOfTransmission = Data([ 0x0a, 0x04 ])        // \n, ^D
        var data = Data()
        data.append(rawREPLCommandCode)
        data.append(_monoclePythonScript)
        data.append(endOfTransmission)

        Util.hexDump(data)

        writeData(data, for: serialRx, peripheral: connectedPeripheral)
        print("[BluetoothManager] Sent Monocle script: \(data.count) bytes")
    }

    // MARK: Helpers

    private func writeData(_ data: Data, for characteristic: CBCharacteristic, peripheral: CBPeripheral) {
        let chunkSize = peripheral.maximumWriteValueLength(for: .withoutResponse)
        var idx = 0
        while idx < data.count {
            let endIdx = min(idx + chunkSize, data.count)
            peripheral.writeValue(data.subdata(in: idx..<endIdx), for: characteristic, type: .withoutResponse)
            idx = endIdx
        }
    }

    private func toString(_ characteristic: CBCharacteristic) -> String {
        if characteristic.uuid == _serialRxCharacteristicUUID {
            return "SerialRx"
        } else if characteristic.uuid == _serialTxCharacteristicUUID {
            return "SerialTx"
        } else if characteristic.uuid == _dataRxCharacteristicUUID {
            return "DataRx"
        } else if characteristic.uuid == _dataTxCharacteristicUUID {
            return "DataTx"
        } else {
            return "UUID=\(characteristic.uuid)"
        }
    }

    // MARK: CBCentralManagerDelegate

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            startScan()
        case .poweredOff:
            // Alert user to turn on Bluetooth
            print("[BluetoothManager] Bluetooth is powered off")
            break
        case .resetting:
            // Wait for next state update and consider logging interruption of Bluetooth service
            break
        case .unauthorized:
            // Alert user to enable Bluetooth permission in app Settings
            print("[BluetoothManager] Authorization missing!")
            break
        case .unsupported:
            // Alert user their device does not support Bluetooth and app will not work as expected
            print("[BluetoothManager] Bluetooth not supported on this device!")
            break
        case .unknown:
           // Wait for next state update
            break
        default:
            break
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? ""
        print("[BluetoothManager] Discovered peripheral: name=\(name), UUID=\(peripheral.identifier), RSSI=\(RSSI)")

        guard name == _monocleName else {
            updateDiscoveredPeripherals()
            return
        }

        updateDiscoveredPeripherals(with: peripheral)

        guard _connectedPeripheral == nil else {
            // Already connected
            return
        }

        // If this is the peripheral we are "paired" to and looking for, connect
        var shouldConnect = peripheral.identifier == selectedDeviceID

        // Otherwise, auto-connect to first device whose RSSI meets the threshold and auto-connect enabled
        if _allowAutoConnectByProximity && RSSI.floatValue >= _rssiAutoConnectThreshold {
            shouldConnect = true
        }

        // Connect
        if shouldConnect {
            print("[BluetoothManager] Connecting to peripheral: name=\(name), UUID=\(peripheral.identifier)")
            connectPeripheral(peripheral)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if peripheral != _connectedPeripheral {
            print("[BluetoothManager] Internal error: Connected to an unexpected peripheral")
            return
        }

        let name = peripheral.name ?? ""

        print("[BluetoothManager] Connected to peripheral: name=\(name), UUID=\(peripheral.identifier)")
        peripheral.delegate = self
        peripheral.discoverServices([ _monocleSerialServiceUUID, _monocleDataServiceUUID ])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if peripheral != _connectedPeripheral {
            print("[BluetoothManager] Internal error: Failed to connect to an unexpected peripheral")
            return
        }

        if let error = error {
            print("[BluetoothManager] Error: Failed to connect to peripheral: \(error.localizedDescription)")
        } else {
            print("[BluetoothManager] Error: Failed to connect to peripheral")
        }

        forgetPeripheral()
        updateDiscoveredPeripherals()
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral != _connectedPeripheral {
            print("[BluetoothManager] Internal error: Disconnected from an unexpected peripheral")
            return
        }

        if let error = error {
            print("[BluetoothManager] Error: Disconnected from peripheral: \(error.localizedDescription)")
        } else {
            print("[BluetoothManager] Error: Disconnected from peripheral")
        }

        forgetPeripheral()
        startScan()
        updateDiscoveredPeripherals()
    }

    // MARK: CBPeripheralDelegate

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if peripheral != _connectedPeripheral {
            print("[BluetoothManager] Internal error: peripheral(_:, didDiscoverServices:) called unexpectedly")
            return
        }

        if let error = error {
            print("[BluetoothManager] Error discovering services on peripheral UUID=\(peripheral.identifier): \(error.localizedDescription)")
            return
        }

        print("didDiscoverServices")
        for service in peripheral.services ?? [] {
            print("  descr=\(service.description) uuid=\(service.uuid)")
        }

        printServices()
        discoverCharacteristics()
    }

    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        if peripheral != _connectedPeripheral {
            print("[BluetoothManager] Internal error: peripheral(_:, didModifyServices:) called unexpectedly")
            return
        }

        print("[BluetoothManager] didModifyServices")
        for service in invalidatedServices {
            print("  descr=\(service.description) uuid=\(service.uuid)")
        }

        if invalidatedServices.contains(where: { $0.uuid == _monocleSerialServiceUUID }) || invalidatedServices.contains(where: { $0.uuid == _monocleDataServiceUUID}) {
            forgetCharacteristics()
        }

        peripheral.discoverServices( [ _monocleSerialServiceUUID, _monocleDataServiceUUID ])
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if peripheral != _connectedPeripheral {
            print("[BluetoothManager] Internal error: peripheral(_:, didDiscoverCharacteristicsFor:, error:) called unexpectedly")
            return
        }

        printCharacteristics(of: service)
        saveCharacteristics(of: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[BluetoothManager] Error: Value update for \(toString(characteristic)) failed: \(error.localizedDescription)")
            return
        }

        if characteristic.uuid == _serialTxCharacteristicUUID {
            // Received value on serial service
            print("[BluetoothManager] Received SerialTx value!")
            if let value = characteristic.value {
                let str = String(decoding: value, as: UTF8.self)
                print("[BluetoothManager] SerialTx value UTF-8 from Monocle: \(str)")

                // Check for MicroPython
                if _waitingForMicroPython, str.count >= 4 {
                    let last3Idx = str.index(str.endIndex, offsetBy: -4)
                    let last3Chars = String(str[last3Idx...])
                    if last3Chars == ">>> " {
                        print("[BluetoothManager] MicroPython detected")
                        _waitingForMicroPython = false

                        // Monocle program used to be transmitted here but this can create a race.
                        // It has been observed that this callback can fire before the SerialRx
                        // characteristic is available, making it impossible for program to be
                        // transmitted at this time.
                    }
                }

            } else {
                print("[BluetoothManager] Error: Unable to access SerialTx value!")
            }
        } else if characteristic.uuid == _dataTxCharacteristicUUID {
            print("[BluetoothManager] Received DataTx value!")
            if let value = characteristic.value, value.count >= 4 {
                let command = String(decoding: value[0..<4], as: UTF8.self)
                print("[BluetoothManager] DataTx value UTF-8 from Monocle: \(command)")

                // Handle messages from Monocle app
                if command.starts(with: "ast:") {
                    // Delete currently stored audio and prepare to receive new audio sample over
                    // multiple packets
                    print("[BluetoothManager] Received audio start command")
                    _audioData.removeAll(keepingCapacity: true)
                } else if command.starts(with: "dat:") {
                    // Append audio data
                    print("[BluetoothManager] Received audio data packet (\(value.count - 4) bytes)")
                    _audioData.append(value[4...])
                } else if command.starts(with: "aen:") {
                    // Audio finished, submit for transcription
                    print("[BluetoothManager] Received complete audio buffer (\(_audioData.count) bytes)")
                    if _audioData.count.isMultiple(of: 2) {
                        convertAudioToLittleEndian()
                        if let pcmBuffer = AVAudioPCMBuffer.fromMonoInt16Data(_audioData, sampleRate: 16000) {
                            monocleVoiceQuery.send(pcmBuffer)
                        } else {
                            print("[BluetoothManager] Error: Unable to convert audio data to PCM buffer")
                        }
                    } else {
                        print("[BluetoothManager] Error: Audio buffer is not a multiple of two bytes")
                    }
                } else if command.starts(with: "pon:") {
                    // Transcript acknowledgment
                    print("[BluetoothManager] Received pong (transcription acknowledgment)")
                    let uuidStr = String(decoding: value[4...], as: UTF8.self)
                    if let uuid = UUID(uuidString: uuidStr) {
                        monocleTranscriptionAck.send(uuid)
                    }
                }
            } else {
                print("[BluetoothManager] Error: Unable to access DataTx value!")
            }
        }
    }

    // MARK: Audio Buffer Manipulation

    private func convertAudioToLittleEndian() {
        var idx = 0
        while (idx + 2) <= _audioData.count {
            let msb = _audioData[idx]
            _audioData[idx] = _audioData[idx + 1]
            _audioData[idx + 1] = msb
            idx += 2
        }
    }
}
