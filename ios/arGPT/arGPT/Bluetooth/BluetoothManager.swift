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

    /// Monocle connected
    @Published var peripheralConnected = PassthroughSubject<UUID, Never>()

    /// Monocle disconnected
    @Published var peripheralDisconnected = PassthroughSubject<Void, Never>()

    /// Data received from Monocle on serial TX characteristic
    @Published var serialDataReceived = PassthroughSubject<Data, Never>()

    /// Data received from Monocle on data TX characteristic
    @Published var dataReceived = PassthroughSubject<Data, Never>()

    /// Sets the device ID to automatically connect to. This is kept separate from
    /// connectedDeviceID to avoid an infinite publishing loop from here -> Settings -> here when
    /// auto-connecting by proximity.
    @Published public var selectedDeviceID: UUID? {
        didSet {
            if let connectedPeripheral = _connectedPeripheral {
                // We have a connected peripheral. See if desired device ID changed and if so,
                // disconnect.
                if selectedDeviceID != connectedPeripheral.identifier {
                    _manager.cancelPeripheralConnection(connectedPeripheral)    // should cause disconnect event
                }
            }
        }
    }

    public var maximumDataLength: Int? {
        return _connectedPeripheral?.maximumWriteValueLength(for: .withoutResponse)
    }

    /// Enables/disables the Bluetooth connectivity. Disconnects from connected peripheral (but
    /// does not unpair it) and stops scanning when set to false. When set to true, will try to
    /// immediately begin scanning.
    public var enabled: Bool {
        get {
            return _enabled
        }

        set {
            _enabled = newValue
            print("[BluetoothManager] \(_enabled ? "Enabled" : "Disabled")")
            if _enabled && _manager.state == .poweredOn {
                startScan()
            } else {
                // Do not attempt to scan anymore
                _manager.stopScan()

                // Disconnect
                if let connectedPeripheral = _connectedPeripheral {
                    // This will cause a disconnect that in turn will cause the peripheral to be
                    // forgotten
                    _manager.cancelPeripheralConnection(connectedPeripheral)
                }
            }
        }
    }

    private var _enabled = false

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

    private var _didSendConnectedEvent = false

    public init(autoConnectByProximity: Bool) {
        _allowAutoConnectByProximity = autoConnectByProximity

        super.init()

        // Ensure manager is instantiated; all logic will then be driven by centralManagerDidUpdateState()
        _ = _manager
    }

    public func sendSerialData(_ data: Data) {
        // Transmit on serial RX
        guard let rx = _serialRx,
              let connectedPeripheral = _connectedPeripheral else {
            return
        }
        writeData(data, for: rx, peripheral: connectedPeripheral)
        print("[BluetoothManager] Sent \(data.count) bytes on SerialRx")
    }

    public func sendData(_ data: Data) {
        // Transmit on data RX
        guard let rx = _dataRx,
              let connectedPeripheral = _connectedPeripheral else {
            return
        }
        writeData(data, for: rx, peripheral: connectedPeripheral)
    }

    public func sendData(text str: String) {
        if let data = str.data(using: .utf8) {
            sendData(data)
        }
    }

    private func startScan() {
        if _manager.isScanning {
            print("[BluetoothManager] Internal error: Already scanning")
            return
        }

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

        // No need to continue scanning
        _manager.stopScan()

        // We do not send the connection event just yet here. We wait for all characteristics to be
        // obtained before doing so
        _didSendConnectedEvent = false
    }

    private func forgetPeripheral() {
        _connectedPeripheral?.delegate = nil
        _connectedPeripheral = nil
        _serialTx = nil
        _serialRx = nil
        _dataTx = nil
        _dataRx = nil

        peripheralDisconnected.send()
        _didSendConnectedEvent = false
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

        // Send connection event when all characteristics obtained
        let haveAllCharacteristics = _serialTx != nil && _serialRx != nil && _dataTx != nil && _dataRx != nil
        if haveAllCharacteristics, !_didSendConnectedEvent {
            peripheralConnected.send(peripheral.identifier)
            _didSendConnectedEvent = true
        }
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
            if enabled {
                startScan()
            }
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
        if enabled {
            startScan()
        }
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
            if let value = characteristic.value {
                serialDataReceived.send(value)
            }
        } else if characteristic.uuid == _dataTxCharacteristicUUID {
            if let value = characteristic.value {
                dataReceived.send(value)
            }
        }
    }
}
