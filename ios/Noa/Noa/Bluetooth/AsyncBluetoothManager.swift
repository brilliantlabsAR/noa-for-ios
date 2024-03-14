//
//  AsyncBluetoothManager.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 12/24/23.
//

//
// API Overview
// ------------
// - Supports one service with a single characteristic to read on (rx) and another to transmit on
//   (tx).
// - When not connected, the manager is always scanning and periodically returns devices found
//   via the discoveredDevices async stream. The stream never ends and can be iterated forever.
//   Updates will stop when a connection is established and the stream will periodically return
//   empty arrays during this time. Devices are returned in descending order by RSSI.
//
//      for await devices in _bluetooth.discoveredDevices {
//          // ... search for your device here ...
//      }
//
// - Establish a connection by calling connect() and retaining the returned object. Only one
//   connection is allowed at a time. Subsequent calls to connect() will try to disconnect the
//   previous connection.
//
//      if let connection = await _bluetooth.connect(to: device) {
//          print("Success!")
//      } else {
//          print("Failed!")
//      }
//
// - When the connection reference is lost, the device will be disconnected.
//
//      connection = nil
//
// - It is possible to forcibly disconnect the current connection without using the connection
//   reference by calling disconnect() on the manager object.
//
//      _bluetooth.disconnect()
//
// - The connection reference contains methods for reading and sending data.
//
//      for try await data in connection.receivedData {
//          print("Received \(data.count) bytes")
//          connection.send(text: "My reply")
//      }
//
// - Disconnects are detected by catching errors on receivedData or through completions on the
//   send methods.
//
//      do {
//          response = try await connection.receivedData
//      } catch let error as AsyncBluetoothManager.StreamError {
//          print("Disconnected: \(error.localizedDescription)")
//      }
//
//      connection.send(text: "Hello") { (error: AsyncBluetoothManager.StreamError?) in
//          if let error = error {
//              print("Disconnected: \(error.localizedDescription)")
//          }
//      }
//
// Programmer Notes
// ----------------
// - Only one connection permitted at a time. Subsequent connect() calls will close the previous
//   connection.
// - Connections are not fully formed until required characteristics are discovered. The actual
//   underlying peripheral connection is established quickly but until characteristics are
//   obtained, no connection object is created.
// - Caller must maintain a strong reference to Connection object. If it is destroyed, the
//   connection is closed and the receive data stream is terminated. We try to finish the stream
//   first before cleaning up any other state (including the peripheral connection itself) so
//   that the error returned by the stream indicates the connection was closed *intentionally*, and
//   not disconnected/lost.
// - The disconnect logic is confusing and has a degree of redundancy built into it. Any given
//   disconnect pathway can end up triggering others, too. Our API signals connection errors via
//   the async data stream and this should ensure only the "first" disconnect reason actually
//   bubbles up to the caller.
// - The purpose of connectionID is to guard against the case where a new connection is somehow
//   established before we destroy our old one. We don't want to wipe out the connection reference
//   if it has already been replaced with a new connection, so we check that we have the intended
//   object. If not, it was already removed.
// - Scanning is expensive. We stop it when connecting and then resume it on disconnect.
// - Be careful with threads. We create a queue and all CoreBluetooth calls must happen there. All
//   class members must be accessed consistently on this queue alone.
// - Thanks to Yasuhito Nagamoto for his async Bluetooth example here:
//   https://github.com/ynagatomo/microbit-swift-controller
//
// Bluetooth State Restoration
// ---------------------------
// Bluetooth state restoration allows the application to be relaunched in the background in
// response to Bluetooth events (messages, reconnect, etc.) after iOS has suspended it. State
// preservation and restoration is enabled by:
//
//  1. Passing CBCentralManagerOptionRestoreIdentifierKey to CBCentralManager's initializer.
//  2. Implementing UIApplicationDelegate's application(_:,didFinishLaunchingWithOptions:) method
//     to ensure that the Bluetooth manager and any other require application components are
//     instantiated (it seems that the SwiftUI views will not necessarily be instantiated until
//     the user foregrounds the app again).
//  3. Enabling the required Bluetooth background mode for the project.
//  4. Handling centralManager(_:,willRestoreState:), which is called first after
//     AsyncBluetoothManager is instantiated during the restoration process.
//
// We restore the peripheral by holding on to it and also updating discoveredDevices. The app's
// connect loop, once brought up, will find it and initiate a connection via
// AsyncBluetoothManager's connect() method (even though it may already be "connected" internally),
// which in turn handles the case of an existing peripheral being known.
//
// It has been observed that the order of delegate calls during restoration is:
//
//  1. centralManager(_:,willRestoreState:) -- we update discoveredDevices here, surfacing any
//     restored peripherals. This seems to always be called first.
//  2. centralManagerDidUpdateState(_:) -- switches to the .poweredOn state. We begin scanning
//     here, in case the peripheral is no longer connected.
//  3. centralManager(_:,didConnect:) -- unsure whether this happens before or after the above but
//     it results in our finishConnecting() method being called, which saves a reference to the
//     peripheral that is used when connect() is later called by the app. Restored peripherals can
//     already be connected and it appears that CoreBluetooth calls this method as part of the
//     restoration process.
//
// For more information, see Apple's documentation:
//
// - https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules
//

import CoreBluetooth
import os

class AsyncBluetoothManager: NSObject {
    // MARK: Internal state

    private let _queue = DispatchQueue(label: "xyz.brilliant.argpt.bluetooth", qos: .userInitiated)

    private lazy var _manager: CBCentralManager = {
        return CBCentralManager(delegate: self, queue: _queue, options: [CBCentralManagerOptionRestoreIdentifierKey: "AsyncBluetoothManager"])
    }()

    private let _peripheralDescriptions: [PeripheralDescription]

    private var _discoveredPeripherals: [(peripheral: Peripheral, timeout: TimeInterval)] = []
    private var _discoveryTimer: Timer?

    private var _discoveredDevicesContinuation: AsyncStream<[Peripheral]>.Continuation!
    private var _connectContinuation: AsyncStream<Connection>.Continuation?
    private weak var _connection: Connection?

    private var _connectedPeripheral: CBPeripheral?
    private var _characteristicByUUID: [CBUUID: CBCharacteristic] = [:]

    // MARK: API - Peripheral description

    struct CharacteristicDescription {
        let uuid: CBUUID
        let notify: Bool
    }

    struct ServiceDescription {
        let uuid: CBUUID
        let characteristics: [CharacteristicDescription]
    }

    struct PeripheralDescription {
        let services: [ServiceDescription]
    }

    // MARK: API - Error definitions

    enum StreamError: Error {
        case connectionLost         // closed because underlying connection to peripheral was lost somehow
        case connectionReplaced     // closed because connect() was called again
        case connectionClosed       // closed intentionally by e.g. a disconnect() call
        case utf8EncodingFailed     // failed to convert string to data and could not send
    }

    // MARK: API - Discovered peripheral object

    struct Peripheral {
        let peripheral: CBPeripheral
        let rssi: Float
        let restored: Bool
    }
    // MARK: API - Connection object

    class Connection {
        fileprivate var _characteristicByUUID: [CBUUID: CBCharacteristic]
        private var _streamByUUID: [CBUUID: AsyncThrowingStream<Data, Error>] = [:]
        private var _streamContinuationByUUID: [CBUUID: AsyncThrowingStream<Data, Error>.Continuation] = [:]

        //private(set) var receivedData: AsyncThrowingStream<Data, Error>!
        //fileprivate var _receivedDataContinuation: AsyncThrowingStream<Data, Error>.Continuation?

        private weak var _queue: DispatchQueue?
        private weak var _peripheral: CBPeripheral?
        private let _maximumWriteLengthWithResponse: Int
        private let _maximumWriteLengthWithoutResponse: Int
        private weak var _tx: CBCharacteristic?
        private weak var _asyncManager: AsyncBluetoothManager?
        fileprivate let connectionID = UUID()
        private var _error: StreamError?

        fileprivate init(queue: DispatchQueue, asyncManager: AsyncBluetoothManager, peripheral: CBPeripheral, characteristicByUUID: [CBUUID: CBCharacteristic]) {
            _queue = queue
            _peripheral = peripheral
            _characteristicByUUID = characteristicByUUID
            _asyncManager = asyncManager
            _maximumWriteLengthWithResponse = peripheral.maximumWriteValueLength(for: .withResponse)
            _maximumWriteLengthWithoutResponse = peripheral.maximumWriteValueLength(for: .withoutResponse)

            // Create all the async streams (we could further optimize this by only creating
            // streams for readable characteristics)
            for uuid in characteristicByUUID.keys {
                _streamByUUID[uuid] = AsyncThrowingStream<Data, Error> { [weak self] continuation in
                    self?._streamContinuationByUUID[uuid] = continuation
                }
            }
        }

        deinit {
            // Destruction of this object closes the connection
            _queue?.async { [weak _asyncManager, connectionID] in
                // If connection was already destroyed due to another error, that will have already
                // occurred and takes precedence. If connectionn is closing due to going out of
                // scope and deinit is called, .connectionClosed is the correct error.
                _asyncManager?.disconnect(connectionID: connectionID, with: .connectionClosed)
            }
        }

        fileprivate func yieldData(_ data: Data, characteristicUUID: CBUUID) {
            _streamContinuationByUUID[characteristicUUID]?.yield(data)
        }

        fileprivate func closeStream(with error: StreamError) {
            for continuation in _streamContinuationByUUID.values {
                continuation.finish(throwing: error)
            }
            _error = error
        }

        func receivedData(from characteristicUUID: CBUUID) -> AsyncThrowingStream<Data, Error>? {
            return _streamByUUID[characteristicUUID]
        }

        func maximumWriteLength(for writeType: CBCharacteristicWriteType) -> Int {
            return writeType == .withResponse ? _maximumWriteLengthWithResponse : _maximumWriteLengthWithoutResponse
        }

        func send(data: Data, to characteristicUUID: CBUUID, response: Bool = false, completionQueue: DispatchQueue = .main, completion: ((StreamError?) -> Void)? = nil) {
            _queue?.async { [weak self] in
                if let error = self?._error, let completion = completion {
                    // Connection is already closed
                    completionQueue.async {
                        completion(error)
                    }
                }

                guard let self = self,
                      let peripheral = _peripheral,
                      let characteristic = _characteristicByUUID[characteristicUUID] else {
                    return
                }

                let writeType: CBCharacteristicWriteType = response ? .withResponse : .withoutResponse
                let chunkSize = peripheral.maximumWriteValueLength(for: writeType)
                var idx = 0
                while idx < data.count {
                    let endIdx = min(idx + chunkSize, data.count)
                    peripheral.writeValue(data.subdata(in: idx..<endIdx), for: characteristic, type: writeType)
                    idx = endIdx
                }

                if let completion = completion {
                    // Indicate successful send
                    completionQueue.async {
                        completion(nil)
                    }
                }
            }
        }

        func send(text: String, to characteristicUUID: CBUUID, response: Bool = false, completionQueue: DispatchQueue = .main, completion: ((StreamError?) -> Void)? = nil) {
            _queue?.async { [weak self] in
                if let data = text.data(using: .utf8) {
                    self?.send(data: data, to: characteristicUUID, response: response, completionQueue: completionQueue, completion: completion)
                } else {
                    // Indicate encoding failure
                    completionQueue.async {
                        completion?(.utf8EncodingFailed)
                    }
                }
            }
        }
    }

    // MARK: API - Properties and methods

    private(set) var discoveredDevices: AsyncStream<[Peripheral]>!

    init(peripherals: [PeripheralDescription]) {
        _peripheralDescriptions = peripherals
        Self.verifyPeripheralUniqueness(peripherals)

        super.init()

        discoveredDevices = AsyncStream<[Peripheral]>([Peripheral].self, bufferingPolicy: .bufferingNewest(1)) { continuation in
            _queue.async {
                // Continuation will be accessed from Bluetooth queue
                self._discoveredDevicesContinuation = continuation
            }
        }

        // Start Bluetooth manager. Ensure manager is instantiated because all logic will be driven
        // by centralManagerDidUpdateState().
        _queue.async {
            _ = self._manager
        }
    }

    func connect(to peripheral: CBPeripheral) async -> Connection? {
        // Create an async stream we will use to await the first connection-related event (there
        // should only ever be one: successful or unsuccessful connection).
        log("Connecting to \(peripheral.identifier)...")
        let connectStream = AsyncStream<Connection> { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }

            _queue.async { [weak self] in
                guard let self = self else {
                    continuation.finish()
                    return
                }

                // Disconnect any existing peripheral, unless it is same peripheral we are trying
                // to connect to. As far as I can tell, this occurs because
                // centralManager(_:,didConnect:) can be called during the restoration process and
                // we call finishConnecting() there, which sets _connectedPeripheral. Therefore, we
                // must be prepared for a connected device already existing.
                if let existingPeripheral = _connectedPeripheral {
                    if existingPeripheral == peripheral {
                        // Already have this peripheral, just make sure to refresh service and
                        // characteristics to be sure
                        _connectContinuation = continuation // don't forget this because we are returning early!
                        finishConnecting(to: peripheral)    // refreshes characteristics and finishes the continuation
                        _manager.stopScan()
                        return
                    }
                    _manager.cancelPeripheralConnection(existingPeripheral)
                    _connection?.closeStream(with: .connectionReplaced)
                    _connection = nil
                    forgetPeripheral()
                }

                precondition(_connectContinuation == nil)   // connect() is not reentrant
                _connectContinuation = continuation

                precondition(_connectedPeripheral == nil)
                _manager.stopScan() // no need to continue scanning
                log("Stopped scanning")

                if peripheral.state == .connected {
                    // This peripheral was probably restored
                    log("Already connected to peripheral")
                    finishConnecting(to: peripheral)
                } else {
                    log("Connecting for first time to peripheral")
                    _manager.connect(peripheral)
                }
            }
        }

        // Only care about first event
        var it = connectStream.makeAsyncIterator()
        let connection = await it.next()
        _queue.async { [weak self] in
            // Safe for connect() to be called again
            self?._connectContinuation = nil

            // Retain connection. Weak because if user disposes of it, there is no way to get it
            // back anyway, so no point in risking a retain cycle.
            self?._connection = connection
        }
        log("Connection \(connection == nil ? "not " : "")established")
        return connection
    }

    func disconnect() {
        log("Disconnecting...")
        _queue.async { [weak self] in
            guard let self = self else { return }

            // If a connection exists, kill it
            if let connection = _connection {
                disconnect(connectionID: connection.connectionID, with: .connectionClosed)
            } else {
                startScan()
            }

            // In case of a partially-formed connection, make sure to disconnect the peripheral,
            // which will cause it to be forgotten
            if let peripheral = _connectedPeripheral {
                _manager.cancelPeripheralConnection(peripheral)
                forgetPeripheral()
            }

            // Have observed instances where after we call peripheral connect(), nothing happens
            // and CoreBluetooth gets stuck. Canceling peripheral connection does nothing. We are
            // still in a "connecting" state. Disrupt it.
            _connectContinuation?.finish()
        }
    }

    // MARK: Internal methods

    fileprivate func disconnect(connectionID: UUID, with error: StreamError) {
        if let connection = _connection, connection.connectionID == connectionID {
            // connect() can already replace an existing connection. Need to guard against
            // accidentally closing the subsequent connection, which would happen if the old
            // connection object was destroyed much later.
            log("Connection removed")
            _connection?.closeStream(with: error)
            _connection = nil
            if let peripheral = _connectedPeripheral {
                _manager.cancelPeripheralConnection(peripheral)
                forgetPeripheral()
            }
            startScan()
        }
    }

    private func startScan() {
        if _manager.isScanning {
            log("Warning: Already scanning!")
        }

        _manager.scanForPeripherals(withServices: getServiceUUIDsToScanFor(), options: [CBCentralManagerScanOptionAllowDuplicatesKey: true ])
        log("Scan initiated: \(getServiceUUIDsToScanFor())")

        // Create a timer to update discoved peripheral list. Timers can only be scheduled from
        // main queue, evidently. This is so silly.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            _discoveryTimer?.invalidate()
            _discoveryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] (timer: Timer) in
                self?._queue.async { [weak self] in
                    self?.updateDiscoveredPeripherals()
                }
            }
        }
    }

    private func updateDiscoveredPeripherals(with peripheral: CBPeripheral? = nil, rssi: Float = -.infinity, restored: Bool = false) {
        // Delete anything that has timed out
        let now = Date.timeIntervalSinceReferenceDate
        var numPeripheralsBefore = _discoveredPeripherals.count
        _discoveredPeripherals.removeAll { now >= $0.timeout }
        var didChange = numPeripheralsBefore != _discoveredPeripherals.count

        // If we are adding a peripheral, remove dupes first
        if let peripheral = peripheral {
            numPeripheralsBefore = _discoveredPeripherals.count
            _discoveredPeripherals.removeAll { $0.peripheral.peripheral.isEqual(peripheral) }
            _discoveredPeripherals.append((peripheral: Peripheral(peripheral: peripheral, rssi: rssi, restored: restored), timeout: now + 10))  // timeout after 10 seconds
            didChange = didChange || (numPeripheralsBefore != _discoveredPeripherals.count)
        }

        // Publish sorted in descending order by RSSI. Always publish because RSSI is constantly
        // changing.
        let devices = _discoveredPeripherals
            .map { $0.peripheral }
            .sorted { $0.rssi > $1.rssi }
        _discoveredDevicesContinuation?.yield(devices)

        // Only log peripherals on change in peripherals, not RSSI
        if didChange {
            log("Discovered peripherals:")
            for (peripheral, _) in _discoveredPeripherals {
                log("  name=\(peripheral.peripheral.name ?? "<no name>") id=\(peripheral.peripheral.identifier) rssi=\(peripheral.rssi)")
            }
        }
    }

    private func finishConnecting(to peripheral: CBPeripheral) {
        let name = peripheral.name ?? ""
        log("Connected to peripheral: name=\(name), UUID=\(peripheral.identifier)")
        _connectedPeripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices(getServiceUUIDsForPeripheral(peripheral))
    }

    private func forgetPeripheral() {
        _connectedPeripheral?.delegate = nil
        _connectedPeripheral = nil
        forgetCharacteristics()
    }

    private func forgetCharacteristics(forService service: CBService? = nil) {
        if let service = service {
            // Forget only specific service
            for uuid in getCharacteristicUUIDsForService(service) {
                _characteristicByUUID.removeValue(forKey: uuid)
            }
        } else {
            // Forget *all* characteristics
            _characteristicByUUID = [:]
        }
    }

    private static func verifyPeripheralUniqueness(_ peripherals: [PeripheralDescription]) {
        // Ensure no duplicate services or characteristics
        var services: Set<CBUUID> = []
        var characteristics: Set<CBUUID> = []
        for peripheral in peripherals {
            precondition(peripheral.services.count > 0)
            for service in peripheral.services {
                precondition(!services.contains(service.uuid))
                services.insert(service.uuid)
                precondition(service.characteristics.count > 0)
                for characteristic in service.characteristics {
                    precondition(!characteristics.contains(characteristic.uuid))
                    characteristics.insert(characteristic.uuid)
                }
            }
        }
    }

    /// Returns one service from each device because we only need to scan for a single service
    private func getServiceUUIDsToScanFor() -> [CBUUID] {
        return _peripheralDescriptions.map { $0.services[0].uuid }
    }

    private func getServiceUUIDsForPeripheral(_ peripheral: CBPeripheral) -> [CBUUID] {
        // Identify the matching peripheral description and return all of its services, otherwise
        // return *all* services for *all* possible peripherals because we don't know which this
        // is
        if let services = peripheral.services,
           services.count > 0 {
            for service in services {
                if let peripheralDescription = getPeripheralDescriptionForService(service) {
                    return peripheralDescription.services.map { $0.uuid }
                }
            }
        }

        log("Warning: Peripheral reports no known services, need to discover all possible services")
        var serviceUUIDs: [CBUUID] = []
        for peripheralDescription in _peripheralDescriptions {
            for serviceDescription in peripheralDescription.services {
                serviceUUIDs.append(serviceDescription.uuid)
            }
        }
        return serviceUUIDs
    }

    private func getPeripheralDescriptionForService(_ service: CBService) -> PeripheralDescription? {
        for peripheralDescription in _peripheralDescriptions {
            for serviceDescription in peripheralDescription.services {
                if service.uuid == serviceDescription.uuid {
                    return peripheralDescription
                }
            }
        }
        return nil
    }

    private func getCharacteristicUUIDsForService(_ service: CBService) -> [CBUUID] {
        for peripheralDescription in _peripheralDescriptions {
            for serviceDescription in peripheralDescription.services {
                if service.uuid == serviceDescription.uuid {
                    return serviceDescription.characteristics.map { $0.uuid }
                }
            }
        }
        log("Warning: Service \(service.uuid.uuidString) does not exist in peripheral descriptions")
        return []
    }

    private func getCharacteristicDescription(service: CBService, characteristic: CBCharacteristic) -> CharacteristicDescription? {
        guard let peripheralDescription = getPeripheralDescriptionForService(service) else { return nil }
        for serviceDescription in peripheralDescription.services {
            if serviceDescription.uuid == service.uuid {
                for characteristicDescription in serviceDescription.characteristics {
                    if characteristicDescription.uuid == characteristic.uuid {
                        return characteristicDescription
                    }
                }
            }
        }
        return nil
    }

    private func allCharacteristicsDiscovered() -> Bool {
        for peripheralDescription in _peripheralDescriptions {
            for serviceDescription in peripheralDescription.services {
                for characteristicDescription in serviceDescription.characteristics {
                    if !_characteristicByUUID.keys.contains(characteristicDescription.uuid) {
                        return false
                    }
                }
            }
        }
        return true
    }
}

// MARK: CBCentralManagerDelegate

extension AsyncBluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            log("POWERED ON")
            startScan()
        case .poweredOff:
            log("Bluetooth is powered off")
        case .resetting:
            break
        case .unauthorized:
            log("Authorization missing!")
        case .unsupported:
            log("Bluetooth not supported on this device!")
        case .unknown:
            break
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        updateDiscoveredPeripherals(with: peripheral, rssi: RSSI.floatValue)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        finishConnecting(to: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            log("Error: Failed to connect to peripheral: \(error.localizedDescription)")
        } else {
            log("Error: Failed to connect to peripheral")
        }

        forgetPeripheral()
        updateDiscoveredPeripherals()

        // Return nil from stream to indicate connection failure
        //assert(_connectContinuation != nil)   // connect continuation can be nil when we restore and then fail to connect
        _connectContinuation?.finish()

        if let connection = _connection {
            disconnect(connectionID: connection.connectionID, with: .connectionLost)
        } else {
            // disconnect() on a connection will restart scanning, but must also restart in this case
            startScan()
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral != _connectedPeripheral {
            //TODO: have seen this occur and then get stuck because it is not scanning. Should we force disconnect?
            log("Internal error: Disconnected from an unexpected peripheral")
            return
        }

        if let error = error {
            log("Error: Disconnected from peripheral: \(error.localizedDescription)")
        } else {
            log("Disconnected from peripheral")
        }

        forgetPeripheral()
        updateDiscoveredPeripherals()

        // Possible to get a disconnect before connect event being fired (when characteristics are
        // discovered). If still listening for connect event, indicate failure.
        if let continuation = _connectContinuation {
            continuation.finish()
        }

        // Disconnect happened during a connected session. Close connection and remove it.
        if let connection = _connection {
            disconnect(connectionID: connection.connectionID, with: .connectionLost)
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // Handle state restoration by making the device discoverable for connect loop that should
        // have come up with the app
        log("Restored CBCentralManager")
        if let restoredPeripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in restoredPeripherals {
                if peripheral.state == .connected {
                    peripheral.delegate = self
                    updateDiscoveredPeripherals(with: peripheral, rssi: 0, restored: true)
                } else if peripheral.state == .disconnected {
                    peripheral.delegate = self
                    updateDiscoveredPeripherals(with: peripheral, rssi: 0, restored: true)
                }
            }
        }
    }
}

// MARK: CBPeripheralDelegate

extension AsyncBluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if peripheral != _connectedPeripheral {
            log("Internal error: peripheral(_:, didDiscoverServices:) called unexpectedly")
            return
        }

        if let error = error {
            log("Error discovering services on peripheral UUID=\(peripheral.identifier): \(error.localizedDescription)")
            return
        }

        // Discover characteristics
        guard let services = peripheral.services else {
            log("Error: No services attached to peripheral object")
            return
        }
        forgetCharacteristics()
        for service in services {
            let characteristicUUIDs = getCharacteristicUUIDsForService(service)
            if characteristicUUIDs.count > 0 {
                peripheral.discoverCharacteristics(characteristicUUIDs, for: service)
            }
        }
    }

    //TODO: This is not handled correctly. Once a connection is established, these changes will not propagate to an active connection!
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        if peripheral != _connectedPeripheral {
            log("Internal error: peripheral(_:, didModifyServices:) called unexpectedly")
            return
        }

        // If service is invalidated, forget it and rediscover
        var serviceUUIDs: [CBUUID] = []
        for service in invalidatedServices {
            let isKnownService = getPeripheralDescriptionForService(service) != nil
            if isKnownService {
                forgetCharacteristics(forService: service)
                serviceUUIDs.append(service.uuid)
            }
        }
        peripheral.discoverServices(serviceUUIDs)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if peripheral != _connectedPeripheral {
            log("Internal error: peripheral(_:, didDiscoverCharacteristicsFor:, error:) called unexpectedly")
            return
        }

        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                guard let characteristicDescription = getCharacteristicDescription(service: service, characteristic: characteristic) else { continue }
                if characteristicDescription.notify {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
                _characteristicByUUID[characteristic.uuid] = characteristic
                log("Discovered characteristic: \(characteristic.uuid.uuidString)")
            }
        }

        // Send connection event when both characteristics obtained and someone is waiting for it
        //assert(_connectContinuation != nil)
        if allCharacteristicsDiscovered(),
           let continuation = _connectContinuation {
            continuation.yield(Connection(queue: _queue, asyncManager: self, peripheral: peripheral, characteristicByUUID: _characteristicByUUID))
            continuation.finish()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("Error: Value update for \(characteristic.uuid.uuidString) failed: \(error.localizedDescription)")
            return
        }

        // Return data via Connection's receivedData stream
        if let connection = _connection,
           let data = characteristic.value {
            connection.yieldData(data, characteristicUUID: characteristic.uuid)
        }
    }
}

// MARK: Misc. helpers

fileprivate let _logger = Logger()

fileprivate func log(_ message: String) {
    _logger.notice("[AsyncBluetoothManager] \(message, privacy: .public)")
}

extension AsyncBluetoothManager.StreamError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .connectionLost:
            return "Connection to peripheral lost"
        case .connectionReplaced:
            return "Connection replaced by subsequent call to connect()"
        case .connectionClosed:
            return "Connection closed by application"
        case .utf8EncodingFailed:
            return "Failed to encode and send UTF-8 string"
        }
    }
}
