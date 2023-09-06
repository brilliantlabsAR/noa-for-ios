//
//  BluetoothManager.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 7/20/23.
//
//  After initialization, callers must ensure that methods are called on the same queue that was
//  provided. BluetoothManager will not dispatch its own calls. Likewise, all published properties
//  will adhere to Combine's thread safety rules but objects they pass along should not be accessed
//  outside of the Bluetooth queue.
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
    /// Nearby peripherals matching our peripheral name sorted in desceding order of RSSI. This is updated only while not connected.
    @Published private(set) var discoveredDevices = PassthroughSubject<[(deviceID: UUID, rssi: Float)], Never>()

    @Published private(set) var isConnected = false

    /// Peripheral connected
    @Published private(set) var peripheralConnected = PassthroughSubject<UUID, Never>()

    /// Peripheral disconnected
    @Published private(set) var peripheralDisconnected = PassthroughSubject<Void, Never>()

    /// Data received on a subscribed characteristic
    @Published private(set) var dataReceived = PassthroughSubject<(characteristic: CBUUID, value: Data), Never>()

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

    /// RSSI threshold used for proximity-based auto-pairing. The relative signal strength must be greater than or equal to this value.
    public var rssiThreshold: Float = -70

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
                if _manager.state == .poweredOn {
                    _manager.stopScan()
                }

                // Disconnect
                if let connectedPeripheral = _connectedPeripheral {
                    // This will cause a disconnect that in turn will cause the peripheral to be
                    // forgotten
                    _manager.cancelPeripheralConnection(connectedPeripheral)
                }
            }
        }
    }

    public var connectedPeripheral: CBPeripheral? {
        return _connectedPeripheral
    }

    private var _enabled = false

    private let _peripheralName: String
    private let _serviceUUIDs: [CBUUID]
    private let _receiveCharacteristicUUIDs: [CBUUID]   // characteristics on which we receive data
    private let _transmitCharacteristicUUIDs: [CBUUID]  // characteristics on which we transmit data
    private let _characteristicNameByID: [CBUUID: String]

    private let _queue: DispatchQueue

    private lazy var _manager: CBCentralManager = {
        return CBCentralManager(delegate: self, queue: _queue)
    }()
    private var _started = false

    private let _allowAutoConnectByProximity: Bool

    private var _discoveredPeripherals: [(peripheral: CBPeripheral, rssi: Float, timeout: TimeInterval)] = []
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

    private var _characteristicByID: [CBUUID: CBCharacteristic] = [:]

    private var _didSendConnectedEvent = false

    public init(
        autoConnectByProximity: Bool,
        peripheralName: String,
        services: [CBUUID: String],
        receiveCharacteristics: [CBUUID: String],
        transmitCharacteristics: [CBUUID: String],
        queue: DispatchQueue
    ) {
        _peripheralName = peripheralName
        _serviceUUIDs = Array(services.keys)
        _receiveCharacteristicUUIDs = Array(receiveCharacteristics.keys)
        _transmitCharacteristicUUIDs = Array(transmitCharacteristics.keys)
        _allowAutoConnectByProximity = autoConnectByProximity

        var characteristicNameByID: [CBUUID: String] = [:]
        for (id, name) in receiveCharacteristics {
            characteristicNameByID[id] = name
        }
        for (id, name) in transmitCharacteristics {
            characteristicNameByID[id] = name
        }
        _characteristicNameByID = characteristicNameByID

        _queue = queue

        super.init()
    }

    /// Start the Bluetooth manager. Must be called once and only once after init(). As with other
    /// methods and properties, must be called on the Bluetooth queue.
    public func start() {
        precondition(!_started)

        // Ensure manager is instantiated; all logic will then be driven by centralManagerDidUpdateState()
        _ = _manager
        _started = true
    }

    public func send(data: Data, on id: CBUUID, response: Bool = false) {
        guard let characteristic = _characteristicByID[id] else {
            print("[BluetoothManager] Failed to send because characteristic is not available: UUID=\(id)")
            return
        }

        guard let connectedPeripheral = _connectedPeripheral else {
            print("[BluetoothManager] Failed to send because no peripheral is connected")
            return
        }

        writeData(data, on: characteristic, peripheral: connectedPeripheral, response: response)
        print("[BluetoothManager] Sent \(data.count) bytes on \(toString(characteristic))")
    }

    public func send(text str: String, on id: CBUUID) {
        if let data = str.data(using: .utf8) {
            send(data: data, on: id)
        }
    }

    private func startScan() {
        if _manager.isScanning {
            print("[BluetoothManager] Internal error: Already scanning")
        }

        _manager.scanForPeripherals(withServices: _serviceUUIDs, options: [ CBCentralManagerScanOptionAllowDuplicatesKey: true ])
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
        forgetCharacteristics()

        // No need to continue scanning
        _manager.stopScan()

        // We do not send the connection event just yet here. We wait for all characteristics to be
        // obtained before doing so
        _didSendConnectedEvent = false
    }

    private func forgetPeripheral() {
        _connectedPeripheral?.delegate = nil
        _connectedPeripheral = nil
        forgetCharacteristics()

        peripheralDisconnected.send()
        _didSendConnectedEvent = false
    }

    private func forgetCharacteristics() {
        _characteristicByID = [:]
    }

    private func updateDiscoveredPeripherals(with peripheral: CBPeripheral? = nil, rssi: Float = -.infinity) {
        let numPeripheralsBefore = _discoveredPeripherals.count
        var didChange = false

        // Delete anything that has timed out
        let now = Date.timeIntervalSinceReferenceDate
        _discoveredPeripherals.removeAll { $0.timeout >= now }
        if numPeripheralsBefore != _discoveredPeripherals.count {
            didChange = true
        }

        // If we are adding a peripheral, remove dupes first
        if let peripheral = peripheral {
            _discoveredPeripherals.removeAll { $0.peripheral.isEqual(peripheral) }
            _discoveredPeripherals.append((peripheral: peripheral, rssi: rssi, timeout: now + 10))  // timeout after 10 seconds
            didChange = true
        }

        // Update device list and log it
        // Publish sorted in descending order by RSSI
        let devices = _discoveredPeripherals
            .map { (deviceID: $0.peripheral.identifier, rssi: $0.rssi) }
            .sorted { $0 .rssi < $1.rssi }
        discoveredDevices.send(devices)
        if didChange {
            print("[BluetoothManager] Discovered peripherals:")
            for (peripheral, rssi, _) in _discoveredPeripherals {
                print("[BluetoothManager]   name=\(peripheral.name ?? "<no name>") id=\(peripheral.identifier) rssi=\(rssi)")
            }
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
            peripheral.discoverCharacteristics(_receiveCharacteristicUUIDs + _transmitCharacteristicUUIDs, for: service)
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
                let id = characteristic.uuid

                if _receiveCharacteristicUUIDs.contains(id) {
                    _characteristicByID[id] = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                    print("[BluetoothManager] Obtained characteristic: \(toString(characteristic))")
                } else if _transmitCharacteristicUUIDs.contains(id) {
                    _characteristicByID[id] = characteristic
                    print("[BluetoothManager] Obtained characteristic: \(toString(characteristic))")
                }
            }
        }

        // Send connection event when all characteristics obtained
        let haveAllCharacteristics = _characteristicByID.count == Set(_receiveCharacteristicUUIDs + _transmitCharacteristicUUIDs).count // create set because transmit and receive characteristics may be shared
        if haveAllCharacteristics, !_didSendConnectedEvent {
            peripheralConnected.send(peripheral.identifier)
            _didSendConnectedEvent = true
        }
    }

    // MARK: Helpers

    private func writeData(_ data: Data, on characteristic: CBCharacteristic, peripheral: CBPeripheral, response: Bool = false) {
        let chunkSize = peripheral.maximumWriteValueLength(for: .withoutResponse)
        var idx = 0
        while idx < data.count {
            let endIdx = min(idx + chunkSize, data.count)
            peripheral.writeValue(data.subdata(in: idx..<endIdx), for: characteristic, type: response ? .withResponse : .withoutResponse)
            idx = endIdx
        }
    }

    private func toString(_ characteristic: CBCharacteristic) -> String {
        return _characteristicNameByID[characteristic.uuid] ?? "UUID=\(characteristic.uuid)"
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

        guard name == _peripheralName else {
            updateDiscoveredPeripherals()
            return
        }

        updateDiscoveredPeripherals(with: peripheral, rssi: RSSI.floatValue)

        guard _connectedPeripheral == nil else {
            // Already connected
            return
        }

        // If this is the peripheral we are "paired" to and looking for, connect
        var shouldConnect = peripheral.identifier == selectedDeviceID

        // Otherwise, auto-connect to first device whose RSSI meets the threshold and auto-connect enabled
        if _allowAutoConnectByProximity && RSSI.floatValue >= rssiThreshold {
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
        peripheral.discoverServices(_serviceUUIDs)
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
            print("[BluetoothManager] Disconnected from peripheral")
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

        // If any service is invalidated, forget them all and then rediscover. This is probably over-agressive.
        if invalidatedServices.contains(where: { _serviceUUIDs.contains($0.uuid) }) {
            forgetCharacteristics()
        }

        peripheral.discoverServices(_serviceUUIDs)
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

        let id = characteristic.uuid

        if _receiveCharacteristicUUIDs.contains(id) {
            // We have received something
            if let value = characteristic.value {
                dataReceived.send((characteristic: id, value: value))
            }
        }
    }
}
