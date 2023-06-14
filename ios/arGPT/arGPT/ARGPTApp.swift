//
//  ARGPTApp.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 5/1/23.
//

import Combine
import SwiftUI

@main
struct ARGPTApp: App {
    private let _debugTryAudio = true

    private let _settings = Settings()
    private let _chatMessageStore = ChatMessageStore()

    private let _speechToText = SpeechToText()

    private let _m4aWriter = M4AWriter()

    @ObservedObject private var _bluetooth = BluetoothManager(
        monoclePythonScript: Self.loadPythonScript(named: "MonocleApp"),
        autoConnectByProximity: true
    )

    private var _subscribers = Set<AnyCancellable>()

    private let _mockInput = MockInputGenerator()

    private var _controller: Controller?

    @UIApplicationDelegateAdaptor private var _appDelegate: AppDelegate

    @State private var _displaySettings = false

    var body: some Scene {
        WindowGroup {
            ChatView(
                displaySettings: $_displaySettings,
                isMonocleConnected: $_bluetooth.isConnected,
                pairedMonocleID: $_bluetooth.selectedDeviceID,
                onTextSubmitted: { [weak _controller] (query: String) in
                    _controller?.submitQuery(query: query)
                },
                onClearChatButtonPressed: { [weak _controller] in
                    _controller?.clearHistory()
                }
            )
            .environmentObject(_chatMessageStore)
            .fullScreenCover(isPresented: $_displaySettings, content:
            {
                SettingsView(
                    discoveredDevices: $_bluetooth.discoveredDevices,
                    isMonocleConnected: $_bluetooth.isConnected
                )
                .environmentObject(_settings)
            })
        }
    }

    init() {
        _controller = Controller(settings: _settings, bluetooth: _bluetooth, messages: _chatMessageStore)
    }

    private static func loadPythonScript(named filename: String) -> String {
        // Load source code from disk
        let url = Bundle.main.url(forResource: filename, withExtension: "py")!
        let data = try? Data(contentsOf: url)
        guard let data = data,
              let sourceCode = String(data: data, encoding: .utf8) else {
            fatalError("Unable to load Monocle Python code from disk")
        }
        return sourceCode
    }

    /*

    private func runBigTest() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [unowned _chatMessageStore] in
            // Put in a hundred messages initially. This will not auto-scroll because it occurs before the view is rendered.
            for i in 0..<100 {
                let participant = Int.random(in: 0...1) == 0 ? Participant.user : Participant.chatGPT
                _chatMessageStore.putMessage(Message(content: "Hello \(i)", participant: participant))
            }
        }

        // Add 100 more a second later. This should trigger scrolling.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [unowned _chatMessageStore] in
            for i in 100..<200 {
                let participant = Int.random(in: 0...1) == 0 ? Participant.user : Participant.chatGPT
                _chatMessageStore.putMessage(Message(content: "Hello \(i)", participant: participant))
            }
        }

        // After 4 seconds, add a typing-in-progress message so we can observe scrolling a single line
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [unowned _chatMessageStore] in
            let participant = Int.random(in: 0...1) == 0 ? Participant.user : Participant.chatGPT
            _chatMessageStore.putMessage(Message(content: "", typingInProgress: true, participant: participant))
        }

        // After 6 seconds, add final message (which will remove typing in progress message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [unowned _chatMessageStore] in
            let participant = Int.random(in: 0...1) == 0 ? Participant.user : Participant.chatGPT
            _chatMessageStore.putMessage(Message(content: "This is the final message, I swear!", participant: participant))
        }
    }

    private func runLittleTest() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [unowned _bluetooth] in
            _bluetooth.monocleVoiceQuery.send("data from monocle")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [unowned _bluetooth] in
            _bluetooth.monocleVoiceQuery.send("data from monocle")
        }
    }

    */
}
