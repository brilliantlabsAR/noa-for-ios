//
//  CVPixelBuffer+Extensions.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 8/28/23.
//

import CoreVideo

extension CVPixelBuffer {
    func clearAlpha() {
        let format = CVPixelBufferGetPixelFormatType(self)
        guard format == kCVPixelFormatType_32ABGR || format == kCVPixelFormatType_32ARGB else {
            print("[CVPixelBuffer] Error: Pixel buffer must be ARGB or ABGR format")
            return
        }
        CVPixelBufferLockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))
        let byteStride = CVPixelBufferGetBytesPerRow(self)
        let pixelsWide = CVPixelBufferGetWidth(self)
        let pixelsHigh = CVPixelBufferGetHeight(self)
        let offsetToNextLine = byteStride - pixelsWide * 4
        if let address = CVPixelBufferGetBaseAddress(self) {
            let bytes = address.assumingMemoryBound(to: UInt8.self)
            var idx = 0
            for _ in 0..<pixelsHigh {
                for _ in 0..<pixelsWide {
                    bytes[idx] = 0  // first byte is alpha, make pixel clear
                    idx += 4
                }
                idx += offsetToNextLine
            }
        }
        CVPixelBufferUnlockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))
    }

    static func fromRGB332(
        _ data: Data,
        width: Int,
        height: Int,
        redScaleFactor: Float = 1.0,
        greenScaleFactor: Float = 1.0,
        blueScaleFactor: Float = 1.0
    ) -> CVPixelBuffer? {
        precondition(width * height == data.count)

        // Allocate a new buffer
        var newPixelBuffer: CVPixelBuffer?
        let ret = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            nil,
            &newPixelBuffer
        )
        if ret != kCVReturnSuccess {
            print("[CVPixelBuffer] Error: Unable to create pixel buffer from RGB332 image (error code = \(ret))")
            return nil
        }
        guard let pixelBuffer = newPixelBuffer else {
            print("[CVPixelBuffer] Error: Unable to create pixel buffer from RGB332 image")
            return nil
        }

        // Populate it with pixels converted from RGB332 to 32ARGB
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        let byteStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let offsetToNextLine = byteStride - width * 4
        if let address = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let bytes = address.assumingMemoryBound(to: UInt8.self)
            var inIdx = 0
            var outIdx = 0
            for _ in 0..<height {
                for _ in 0..<width {
                    let r = min(255, Int(Float(data[inIdx] >> 5) * 255.0 * redScaleFactor / 7.0))
                    let g = min(255, Int(Float((data[inIdx] >> 2) & 7) * 255.0 * greenScaleFactor / 7.0))
                    let b = min(255, Int(Float(data[inIdx] & 3) * 255.0 * blueScaleFactor / 3.0))
                    inIdx += 1
                    bytes[outIdx] = 0xff    // opaque
                    outIdx += 1
                    bytes[outIdx] = UInt8(r)
                    outIdx += 1
                    bytes[outIdx] = UInt8(g)
                    outIdx += 1
                    bytes[outIdx] = UInt8(b)
                    outIdx += 1

                }
                outIdx += offsetToNextLine
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

        return pixelBuffer;
    }
}
