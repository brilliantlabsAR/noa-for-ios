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
//              print("DIsconnected: \(error.localizedDescription)")
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

import CoreBluetooth
import os

class AsyncBluetoothManager: NSObject {
    // MARK: Internal state

    private let _queue = DispatchQueue(label: "xyz.brilliant.argpt.bluetooth", qos: .default)

    private lazy var _manager: CBCentralManager = {
        return CBCentralManager(delegate: self, queue: _queue, options: [CBCentralManagerOptionRestoreIdentifierKey: "AsyncBluetoothManager"])
    }()

    private let _serviceUUID: CBUUID
    private let _rxCharacteristicUUID: CBUUID
    private let _txCharacteristicUUID: CBUUID

    private var _discoveredPeripherals: [(peripheral: Peripheral, timeout: TimeInterval)] = []
    private var _discoveryTimer: Timer?

    private var _discoveredDevicesContinuation: AsyncStream<[Peripheral]>.Continuation!
    private var _connectContinuation: AsyncStream<Connection>.Continuation?
    private weak var _connection: Connection?

    private var _connectedPeripheral: CBPeripheral?
    private var _rx: CBCharacteristic?
    private var _tx: CBCharacteristic?

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
        private(set) var receivedData: AsyncThrowingStream<Data, Error>!
        fileprivate var _receivedDataContinuation: AsyncThrowingStream<Data, Error>.Continuation?
        private weak var _queue: DispatchQueue?
        private weak var _peripheral: CBPeripheral?
        private let _maximumWriteLengthWithResponse: Int
        private let _maximumWriteLengthWithoutResponse: Int
        private weak var _tx: CBCharacteristic?
        private weak var _asyncManager: AsyncBluetoothManager?
        fileprivate let connectionID = UUID()
        private var _error: StreamError?

        fileprivate init(queue: DispatchQueue, asyncManager: AsyncBluetoothManager, peripheral: CBPeripheral, rx: CBCharacteristic, tx: CBCharacteristic) {
            _queue = queue
            _peripheral = peripheral
            _tx = tx
            _asyncManager = asyncManager
            _maximumWriteLengthWithResponse = peripheral.maximumWriteValueLength(for: .withResponse)
            _maximumWriteLengthWithoutResponse = peripheral.maximumWriteValueLength(for: .withoutResponse)
            receivedData = AsyncThrowingStream<Data, Error> { [weak self] continuation in
                self?._receivedDataContinuation = continuation
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

        fileprivate func closeStream(with error: StreamError) {
            _receivedDataContinuation?.finish(throwing: error)
            _error = error
        }

        func maximumWriteLength(for writeType: CBCharacteristicWriteType) -> Int {
            return writeType == .withResponse ? _maximumWriteLengthWithResponse : _maximumWriteLengthWithoutResponse
        }

        func send(data: Data, response: Bool = false, completionQueue: DispatchQueue = .main, completion: ((StreamError?) -> Void)? = nil) {
            _queue?.async { [weak self] in
                if let error = self?._error, let completion = completion {
                    // Connection is already closed
                    completionQueue.async {
                        completion(error)
                    }
                }

                guard let self = self,
                      let peripheral = _peripheral,
                      let tx = _tx else {
                    return
                }

                let writeType: CBCharacteristicWriteType = response ? .withResponse : .withoutResponse
                let chunkSize = peripheral.maximumWriteValueLength(for: writeType)
                var idx = 0
                while idx < data.count {
                    let endIdx = min(idx + chunkSize, data.count)
                    peripheral.writeValue(data.subdata(in: idx..<endIdx), for: tx, type: writeType)
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

        func send(text: String, response: Bool = false, completionQueue: DispatchQueue = .main, completion: ((StreamError?) -> Void)? = nil) {
            _queue?.async { [weak self] in
                if let data = text.data(using: .utf8) {
                    self?.send(data: data, response: response, completionQueue: completionQueue, completion: completion)
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

    init(
        service: CBUUID,
        rxCharacteristic: CBUUID,
        txCharacteristic: CBUUID
    ) {
        _serviceUUID = service
        _rxCharacteristicUUID = rxCharacteristic
        _txCharacteristicUUID = txCharacteristic

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
        log("Connecting...")
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
                // to connect to. Unsure of how this could happen but it has been observed. At one
                // point, disconnects would cancel a connection without immediately forgetting the
                // peripheral (waiting for the disconect callback to handle that), which may have
                // resulted in this unusual state
                if let existingPeripheral = _connectedPeripheral {
                    if existingPeripheral == peripheral {
                        // Already have this peripheral, just make sure to refresh service and
                        // characteristics to be sure
                        finishConnecting(to: peripheral)
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

        _manager.scanForPeripherals(withServices: [ _serviceUUID ], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true ])
        log("Scan initiated")

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
        peripheral.discoverServices([ _serviceUUID ])
    }

    private func forgetPeripheral() {
        _connectedPeripheral?.delegate = nil
        _connectedPeripheral = nil
        forgetCharacteristics()
    }

    private func forgetCharacteristics() {
        _rx = nil
        _tx = nil
    }

    private func toString(_ characteristic: CBCharacteristic) -> String {
        if characteristic == _rx {
            return "Rx"
        } else if characteristic == _tx {
            return "Tx"
        } else {
            return characteristic.uuid.uuidString
        }
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
        assert(_connectContinuation != nil)
        _connectContinuation?.finish()

        if let connection = _connection {
            disconnect(connectionID: connection.connectionID, with: .connectionLost)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral != _connectedPeripheral {
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
            peripheral.discoverCharacteristics([ _rxCharacteristicUUID, _txCharacteristicUUID ], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        if peripheral != _connectedPeripheral {
            log("Internal error: peripheral(_:, didModifyServices:) called unexpectedly")
            return
        }

        // If service is invalidated, forget it and rediscover
        if invalidatedServices.contains(where: { $0.uuid == _serviceUUID }) {
            forgetCharacteristics()
        }
        peripheral.discoverServices([ _serviceUUID ])
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if peripheral != _connectedPeripheral {
            log("Internal error: peripheral(_:, didDiscoverCharacteristicsFor:, error:) called unexpectedly")
            return
        }

        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                if _rxCharacteristicUUID == characteristic.uuid {
                    _rx = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                    log("Discovered Rx characteristic")
                } else if _txCharacteristicUUID == characteristic.uuid {
                    _tx = characteristic
                    log("Discovered Tx characteristic")
                }
            }
        }

        // Send connection event when both characteristics obtained and someone is waiting for it
        //assert(_connectContinuation != nil)
        if let rx = _rx,
           let tx = _tx,
           let continuation = _connectContinuation {
            continuation.yield(Connection(queue: _queue, asyncManager: self, peripheral: peripheral, rx: rx, tx: tx))
            continuation.finish()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("Error: Value update for \(toString(characteristic)) failed: \(error.localizedDescription)")
            return
        }

        // Return data via Connection's receivedData stream
        if _rx == characteristic,
           let connection = _connection,
           let data = characteristic.value {
            connection._receivedDataContinuation?.yield(data)
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
