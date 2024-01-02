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

    func loadScript(named filename: String, on connection: AsyncBluetoothManager.Connection, run: Bool = false) async throws {
        let filePrefix = NSString(string: filename).deletingPathExtension   // e.g. test.lua -> test
        let script = loadLuaScript(named: filename)
        try await runCommand("f=frame.file.open('\(filename)', 'w')", on: connection)
        let maxCharsPerLine = connection.maximumWriteLength(for: .withoutResponse) - 22 // "f:write('');print(nil)" is 22 characters
        if maxCharsPerLine < "string.char(0x00,)".count {
            fatalError("Bluetooth packet size is too small")
        }
        var idx = 0
        while idx < script.count {
            let (str, numBytes) = encodeNextScriptChunk(script: script, from: idx, maxLength: maxCharsPerLine)
            let command = "f:write('\(str)')"
            print("[FrameControler] Sending: \(command)")
            try await runCommand(command, on: connection)
            idx += numBytes
            print("[FrameController] Uploaded: \(idx) / \(script.count) bytes of \(filename)")
        }
        try await runCommand("f:close()", on: connection)
        if run {
            connection.send(text: "require('\(filePrefix)')")
        }
    }

    private func encodeNextScriptChunk(script: Data, from startIdx: Int, maxLength: Int) -> (String, Int) {
        // Encodes as many bytes from the start index as possible (subject to maxLength) into a
        // string that looks like: "string.char(0x53,0x65,0x67,0x61,...)". This could be made much
        // more efficient by using base 10 because bytes will be a maximum of 3 rather than 4
        // characters and often only 2.
        let numCharsStringStatement = 13    // "string.char()"
        let numCharsFreeForUse = maxLength - numCharsStringStatement
        let numBytes = min(numCharsFreeForUse / 5, script.count - startIdx) // each byte is 5 chars: "0x12,"
        let bytes = script[startIdx..<startIdx+numBytes].map { String(format: "0x%02x", $0) }
        let str = "string.char(\(bytes.joined(separator: ",")))"
        return (str, numBytes)
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
        print("[FrameController] Executed: \(command)")
    }

    private func loadLuaScript(named filename: String) -> Data {
        let url = Bundle.main.url(forResource: filename, withExtension: nil)!
        let data = try? Data(contentsOf: url)
        guard let data = data else {
            fatalError("Unable to load Lua script from disk")
        }
        return data
    }
}
