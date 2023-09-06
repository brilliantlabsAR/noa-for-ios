//
//  RGB343.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 9/4/23.
//

import CoreVideo

func convertARGB8ToRGB343(_ pixelBuffer: CVPixelBuffer) -> Data {
    CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
    defer {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
    }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let byteStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
    var data = Data(count: Int(ceil(Float(width * height * 10) / 8)))

    if let address = CVPixelBufferGetBaseAddress(pixelBuffer) {
        let bytes = address.assumingMemoryBound(to: UInt8.self)
        let offsetToNextLine = byteStride - width * 4

        /*
         * When packing 10 bit "words" into a byte array, the bit offset resets every 4 words (5
         * bytes):
         *
         *  Byte 0   Byte 1   Byte 2   Byte 3   Byte 4   Byte 5
         * +--------+--------+--------+--------+--------+--------+
         * |11111111|11222222|22223333|33333344|44444444|        |
         * +--------+--------+--------+--------+--------+--------+
         */

        let hiMask: [UInt8] = [ 0x00, 0x3f, 0x0f, 0x03 ]    // mask to apply to existing data, first byte
        let loMask: [UInt8] = [ 0x3f, 0x0f, 0x03, 0x00 ]    // mask to apply to existing data, second byte

        var idx = 0             // input byte index
        var outIdx = 0          // output byte index (first of the two bytes to insert into)
        var shiftRightCount = 0 // number of bits to shift right within that first byte
        var phaseIdx = 0        // which "phase" we are in: 0, 1, 2, or 3 (last phase is where a
                                // complete second byte is written and phase resets)

        for _ in 0..<height {
            for _ in 0..<width {
                let r = UInt(bytes[idx + 1])
                let g = UInt(bytes[idx + 2])
                let b = UInt(bytes[idx + 3])
                idx += 4

                let rgb343 = ((r & 0xe0) << 2) |
                             ((g & 0xf0) >> 1) |
                             (b >> 5)

                // Insert into high byte
                data[outIdx] = UInt8(rgb343 >> (shiftRightCount + 2)) | (data[outIdx] & hiMask[phaseIdx])
                outIdx += 1

                // Insert into low byte
                data[outIdx] = UInt8((rgb343 << (8 - shiftRightCount - 2)) & 0xff) | (data[outIdx] & loMask[phaseIdx])

                // If we are at phaseIdx==3 (see diagram above), we have filled up the entire
                // second byte and must advance
                phaseIdx += 1
                if phaseIdx == 4 {
                    outIdx += 1
                    phaseIdx = 0
                }

                // Update shift right count
                shiftRightCount = (shiftRightCount + 2) & 7
            }

            idx += offsetToNextLine
        }
    }

    return data
}
