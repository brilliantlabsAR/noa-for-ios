//
//  FrameController.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 12/27/23.
//

import CoreBluetooth
import Foundation

class FrameController: ObservableObject {
    static let serviceUUID = CBUUID(string: "7a230001-5475-a6a4-654c-8431f6ad49c4")
    static let txUUID = CBUUID(string: "7a230002-5475-a6a4-654c-8431f6ad49c4")
    static let rxUUID = CBUUID(string: "7a230003-5475-a6a4-654c-8431f6ad49c4")

    /// Loads a script from the iPhone's file system and writes it to the Frame's file system.
    /// It does this by sending a series of file write commands with chunks of the script encoded
    /// as string literals. For now, `[===[` and `]===]` are used, which means that scripts may not
    /// use this level of long bracket or higher.
    /// - Parameter filename: File to send.
    /// - Parameter on: Bluetooth connection to send over.
    /// - Parameter run: If true, runs this script file by executing `require('file')` after script
    /// is uploaded.
    func loadScript(named filename: String, on connection: AsyncBluetoothManager.Connection, run: Bool = false) async throws {
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
            print("[FrameController] Uploaded: \(idx) / \(script.count) bytes of \(filename)")
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
                print("Unexpected response: \(response)")
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
}
