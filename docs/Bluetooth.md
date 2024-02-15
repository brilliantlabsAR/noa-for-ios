# Guide to the Bluetooth Implementation in *Noa for iOS*
*by Bart Trzynadlowski - February 15, 2024*

These notes refer to the `bart/frame` branch and its new `AsyncBluetoothManager`. `BluetoothManager` and `MonocleController` are deprecated and will be refactored after the Frame release.

## Objectives

- Bluetooth connectivity between iOS and Frame must be reliable.
- When the app is backgrounded or suspended:
    - Messages from Frame to iOS must not be lost.
    - Response messages must be delivered. Note that there can be considerable (~10-30 seconds) latency in the worst cases between making a request to the Noa server and getting a response back (caused by the LLM and web search stages).
    - Frame must be able to disconnect (e.g., when powered down, out of range) and reconnect seamlessly.
- Preventing the app from being restored after an explicit force quit (swipe up) is acceptable (and may even be desirable) for now.

## A *Tour de Source*

The relevant parts of the app source code are those controlling app life cycle, CoreBluetooth abstraction, connectivity with Frame, and requests to the Noa server.

- `NoaApp.swift`: `AppDelegate` is implemented here and ensures that the app's `FrameController` instance is created by calling `getFrameController()`, which lazily instantiates the object and stores it in a global variable. It is unclear whether Bluetooth restoration brings up the `NoaApp` SwiftUI object (it may be deferred until the user explicitly opens the app again), therefore, `application(_:,didFinishLaunchingWithOptions:)` is used to guarantee it is instantiated.

- `FrameController.swift`: Implements `FrameController`, which controls all setup of and communication with Frame. This class does the following:

    - Instantiates `AsyncBluetoothManager`, for Bluetooth connectivity.
    - Starts two asynchronous tasks:
        1. **Peripheral scanning task:** This just polls `AsyncBluetoothManager`'s async `discoveredDevices` member for detected peripherals and updates the `_nearbyDevices` array that the main task checks.
        2. **Main task:** This looks for and connects to the Frame device (waiting for the "paired" one, if it exists, otherwise the nearest one upon user confirmation), uploads Lua scripts to Frame, and then handles messages until disconnect.
    - Handles incoming messages from Frame, calls the Noa AI server, and delivers responses.

- `AsyncBluetoothManager.swift`: Asynchronous CoreBluetooth handling. Please read the comment block at the top of this file and examine `FrameController`'s `mainTask()` to understand the API it exposes. This class will be discussed in detail in its own section.

- `AIAssistant.swift`: Noa AI server interface. This is instantiated in `FrameController` and is used to send requests to the AI server. Note that the `URLSession` created in `init(configuration:)` can be configured in one of three ways. Currently, `.normal` is used -- an ordinary `URLSession`. `.backgroundData` does not work when the app is backgrounded (or suspended and restored), `.backgroundUpload` seems to cause requests to be enqueued and then all executed when the app is explicitly foregrounded by the user. *The intended uses of these different modes are not well understood.*

## Frame Communication Protocol

- Frame exposes a single service with transmission (TX) and reception (RX) characteristics.
- The Frame firmware understands two types of message packets:
    - **Lua commands**: These are text strings that are executed directly by Frame's Lua interpreter. There is no header; these are just text strings and the first byte is included. The only requirement is that the first byte cannot be 0x01.
    - **Data**: Messages that begin with the byte 0x01 are interpreted as *binary data* and are intended for use by applications (scripts) running on Frame. When Frame receives a message beginning with 0x01, it delivers all the subsequent bytes as a message via a Lua callback that scripts can subscribe to. This format of message is used to implement communication between the Noa iOS app and its scripts running on Frame (which the iOS app uploads using a series of Lua command messages to write script data to Frame's file system).
- The Noa Frame scripts are located in `Noa/Frame Assets/Scripts`. When reading Lua scripts, note that Lua indexing is 1-based not 0-based.
    - The Frame app that will ship consists of `main.lua`, `state.lua`, and `graphics.lua`.
    - Other test scripts may be present, e.g. `test_restore.lua` which is useful for testing Bluetooth restoration mode and simply sends the same message on a timed loop.
- The Noa app communication protocol is described in `FrameController.swift`. See the `MessageID` enum. Data messages used by Noa contain a one byte header identifying the message type (this of course follows the 0x01 that indicates a data message, which is stripped out by the firmware when delivering messages to scripts).
- Messages are broken up into pieces and sent sequentially. From Frame to iOS, the sequence is:
    1. Multimodal start message (`multimodalStart`). Indicates to the app that new data is about to arrive.
    2. Several RGB332 image chunks (`multimodalImage332Chunk`), which are concatenated in the order they arrive. These are a photo captured by the camera.
    3. Several audio chunks (`multimodalAudioChunk`), concatenated together. These are the microphone recording of the user's spoken request.
    4. Multimodal end message (`multimodalEnd`). Indicates all chunks have been sent and that the request can now be processed. The audio and image data are sent to the Noa AI server.
- The response is sent in a similar fashion from iOS to frame, except that `multimodalTextChunk` is used to send the textual response that Frame will display. Eventually, 4-bit palettized images will also be occasionally sent.

## AsyncBluetoothManager

`AsyncBluetoothManager` exposes a friendlier asynchronous interface to CoreBluetooth. In particular, it makes it simpler to handle sequences of back-and-forth signalling with straightforward, linear code rather than state machines and callback-based code. For example, when `FrameController` sends Lua commands to Frame, it waits for a response before proceeding. **A major deficiency** of the current implementation is that there is no way to specify timeouts when using `await`. It is probably possible to build an interface that supports this somehow but the implementation will almost certainly be complex and ugly.

For a description of the interface, read the comment block atop `AsyncBluetoothManager.swift`.

This section will focus on explaining specific code paths in `AsyncBluetoothManager`.

### Queue

A private `DispatchQueue` is created and stored in `_queue`. All CoreBluetooth delegate methods should execute on this queue, which means that most private members of `AsyncBluetoothManager` can only be accessed from this queue. This necessitates considerable gymnastics throughout the code because public methods are intended to be accessed from another queue  (e.g., the application main queue).

**Question:** Is thread safety being handled correctly? Is hand-off between the main and Bluetooth queues being managed correctly in each case?

### Async Building Blocks: *AsyncStream<T>* and *AsyncStream<T>.Continuation*

`AsyncStream<T>` is the async data structure used to provide interfaces that can be awaited with `await`. It is a FIFO queue of objects that can be awaited until a new object is available. The stream can be terminated and will return `nil` when that happens.

When instantiated, an associated *continuation* object is provided. This is effectively the *write* end of the stream, used for passing in objects and also to terminate the stream.

The simplest example to start with is the public `discoveredDevices` property:

```
    private(set) var discoveredDevices: AsyncStream<[Peripheral]>!
```

It is created in the initializer:

```
    discoveredDevices = AsyncStream<[Peripheral]>([Peripheral].self, bufferingPolicy: .bufferingNewest(1)) { continuation in
        _queue.async {
            // Continuation will be accessed from Bluetooth queue
            self._discoveredDevicesContinuation = continuation
        }
    }
```

This is a stream of `AsyncBluetoothManager.Peripheral` objects (a simple wrapper around `CBPeripheral` with some extra data). In fact, it returns an *array* of peripherals: all currently known peripherals discovered by CoreBluetooth. Because we don't care about stale devices, we make the stream hold only a single element -- the latest one. If the stream is not being awaited, data pushed into it will overwrite previous data, which is exactly what we want. This is what `.bufferingNewest(1)` means.

The stream initializer takes a completion method that is used to deliver the continuation object. This completion executes immediately and is used to save the continuation in `_discoveredDevicesContinuation`. The operation is performed on the Bluetooth queue because this member is only ever accessed from inside of CoreBluetooth delegate callbacks. Now, `FrameController` can pull values from `discoveredDevices` and `AsyncBluetoothManager` will push them using `_discoveredDevicesContinuation`. This stream is never terminated and is always active.

`AsyncBluetoothManager` creates three streams:

1. `discoveredDevices` / `_discoveredDevicesContinuation`: Peripherals discovered during scanning.
2. `_connectionContinuation`: Delivers `Connection` objects, which represent a connected peripheral and are used to send/receive data. The actual stream itself is not retained explicitly but awaited in the `connect(to:)` method. Either a `Connection` object will successfully be produced or the connection fails and the stream is terminated and `nil` returned from `connect(to:)`.
3. `receivedData` / `_receivedDataContinuation`: Members of the `Connection` object. Data received via CoreBluetooth's `peripheral(_:,didUpdateValueFor:,error:)` is pushed here if a connection is present.

The connect/disconnect flow is by far the most complicated.

### Initial Scan

There are several places where `startScan()` is called (and there are likely errors in the logic). Initially, the process is kicked off when CoreBluetooth enters the `.poweredOn` state:

1. `init(service:,rxCharacteristic:,txCharacteristic:)` kicks off the process by reading `_manager`, which lazily instantiates `CBCentralManager`. From this point onwards, `_manager` contains the `CBCentralManager`.
2. Instantiating the manager starts the CoreBluetooth state machine. The only state we handle in `centralManagerDidUpdateState(_:)` is `.poweredOn`, and we use it to start scanning for peripherals with `startScan()`.
3. `startScan()` calls the central manager's `scanForPeripherals(withServices:,options:)` method and creates a timer that periodically executes to clear out all known peripherals. The idea behind this is that while scanning, valid peripherals seem to be updated frequently as their RSSI changes. But there is no way to detect when peripherals drop out, so we periodically cull them. If they have actually disappeared, they will not re-emerge during the scan.

### The Concept of a Connection

`AsyncBluetoothManager` defines a connection differently than CoreBluetooth. It requires:

1. A connected peripheral.
2. All required characteristics to have been obtained (`CBCharacteristic` objects for both the RX and TX characteristics).

This adds complexity to connection management and creates states where a peripheral is "connected" according to CoreBluetooth but not according to our API because characteristics have not yet been discovered.

The `connect(to:)` method is called when a peripheral has been identified via `discoveredDevices`. It is asynchronous and will attempt to form a complete connection, returning a `Connection` object or `nil` upon failure. The connection flow is:

1. `FrameController` awaits `connect(to:)` when it has identified a Frame device to connect to.
2. `connect(to:)` on `AsyncBluetoothManager` is an async function returning `Connection?`.
3. `connect(to:)` first instantiates a new `AsyncStream<Connection>` to which we will push the formed connection when CoreBluetooth establishes it, or terminate with a failure (`nil`) if it fails.
4. For now, let's skip past the large completion handler that sets up the continuation to the end of `connect(to:)`, an iterator is obtained for the stream and awaited for the next object (which will be either a successful connection or `nil`). Once this is obtained, the continuation is removed and the connection result is returned.
5. Inside the completion handler executed when `AsyncStream<Connection>` is created, we first check to see if any existing connection exists. If so, we close it. Only one `Connection` may exist at a time and is replaced if `connect(to:)` is called without first disconnecting. There is a subtlety here: we check to see whether CoreBluetooth thinks it is already connected to the peripheral. It is not entirely clear how this state can arise, or whether it does anymore, but it has been observed in the past. See the comment in the code.
6. We stop scanning because we are about to connect and no longer need to look for devices.
7. If the peripheral is already in a connected state (which could happen if it was restored via CoreBluetooth restoration), we proceed to `finishConnecting(to:)`. Otherwise, we initiate a connection by calling the central manager's `connect()` method. At this point, we wait for CoreBluetooth. `connect(to:)` sleeps while it awaits the async stream to deliver a result.
8.  `centralManager(_:,didConnect:)` or `centralManager(_:,didFailToConnect:,error:)` will be called next. The latter terminates the connection continuation by invoking `_connectContinuation?.finish()`, which pushes a `nil` through the async stream. A somewhat complicated disconnect flow is invoked, discussed later.
9. In the successful connection case, `finishConnecting(to:)` is called.
10. `finishConnecting(to:)` sets the `_connectedPeripheral` member to retain the peripheral and then calls `discoverServices()` on the peripheral, in order to ultimately obtain the characteristics.
11. `peripheral(_:,didDiscoverServices:)` is expected to be called next. It calls `discoverCharacteristics(_:,for:)`.
12. `peripheral(_:,didDiscoverCharacteristicsFor:,error:)` fires next. The RX and TX characteristics are obtained and saved in `_rx` and `_tx`, respectively. Now the connection is fully formed and a `Connection` object is instantiated and pushed to the stream. The stream is now finished.
13. Back in `connect(to:)`, where the stream was being awaited, the connection object comes through. This happens in the main thread, from where this method was called. A completion is dispatched to the Bluetooth queue to retain a *weak* reference to the connection internally and to delete the continuation, which is no longer needed. A weak reference is retained because only the caller of `connect(to:)` should maintain ownership of the connection. When the connection is deleted, the disconnect flow is triggered. To avoid a circular reference keeping it alive, only a weak reference is retained by `AsyncBluetoothManager`.
14. The `Connection` object contains methods for writing to the peripheral and a stream to receive data on.

### Disconnection

There are several disconnect pathways. Ultimately, they must throw an error on the `Connection` object's `receivedData` stream, which is an `AsyncThrowingStream<Data>`, meaning it can throw errors. There are two explicit ways to disconnect but they are never used (releasing all references to `Connection` or calling `disconnect()`). Much of the complexity in the disconnect flow stems from having to support these explicit disconnect methods or API misuse (such as calling `connect(to:)` twice in a row without an explicit disconnect).

#### Peripheral Disconnection Flow

If the peripheral connection is lost, `centralManager(_:,didDisconnectPeripheral:,error:)` is called. The connection stream is closed and `disconnect(connectionID:,with:)` is called. This method performs the following actions:

1. Closes the `receivedData` stream on the current connection object with an error.
2. Calls `cancelPeripheralConnection()` on the central manager to ensure the peripheral is really disconnected.
3. Forgets the peripheral objects and its characteristic objects.
4. Begins a new scan with `startScan()`.

Note that there is an edge case where `disconnect(connectionID:,with:)` can be called after the connection has been replaced. This could occur through API misuse if a stale `Connection` object is retained after calling `connect(to:)` again, and only later deleted. Otherwise, `_connection` is only ever nilled out in this disconnect method and `connect(to:)` when replacing a peripheral. Therefore, `startScan()` should always end up being called.

**Question:** Is it nevertheless possible that we end up in a state where `startScan()` is not called?

### Restoration

CoreBluetooth restoration should be configured correctly with all necessary background modes and handlers set up. However, when `application(_:,didFinishLaunchingWithOptions:)` is called, the expected restoration key is never found for some reason.

**Question:** Is the project correctly set up for Bluetooth restoration?

Restoration is intended to work as follows:

1. When the app is restored, `application(_:,didFinishLaunchingWithOptions:)` is called but `NoaApp` (SwiftUI) may not be instantiated. The application delegate method instantiates a `FrameController`.
2. The `FrameController` instance instantiates `AsyncBluetoothManager` and also, crucially, kicks off its two tasks, including to scan for peripherals.
3. `centralManager(_:,willRestoreState:)` should be called next. It is unclear whether this happens before or after the powered-on state is reached.
4. For each restored peripheral, regardless of its connection status, `updateDiscoveredPeripherals(with:,rssi:,restored:)` is called. Their RSSI is unknown (it would take time and complexity to query it).
5. `updateDiscoveredPeripherals(with:,rssi:,restored:)` publishes these peripherals on `discoveredDevices`.
6. `FrameController` receives these and attempts to connect to the paired one using the connection flow described earlier.
7. In the stream completion in `connect(to:)`, if the restored peripheral is already connected, there is a case that handles that and proceeds to `finishConnecting(to:)` rather than the usual pathway of calling `connect()` on the central.

### A Note on Pairing

Frame bonds securely to iOS. This is transparent to the iOS app, which merely saves the device UUID in `UserDefaults`. The "paired" device is therefore the one specified in settings. If no value exists, the app considers itself to be unpaired and will wait for the user to actually confirm the initial connection.
