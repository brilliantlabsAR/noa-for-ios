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

    static func fromRGB332(_ data: Data, width: Int, height: Int) -> CVPixelBuffer? {
        precondition(width * height == data.count)

        // Convert to linear ARGB8 buffer
        var rgb = Data(count: width * height * 4)
        var outIdx = 0
        for i in 0..<data.count {
            let r = min(255, Int(Float(data[i] >> 5) * 255.0 / 7.0))
            let g = min(255, Int(Float((data[i] >> 2) & 7) * 255.0 / 7.0))
            let b = min(255, Int(Float(data[i] & 3) * 255.0 / 3.0))
            rgb[outIdx] = 0xff
            outIdx += 1
            rgb[outIdx] = UInt8(r)
            outIdx += 1
            rgb[outIdx] = UInt8(g)
            outIdx += 1
            rgb[outIdx] = UInt8(b)
            outIdx += 1
        }

        // Produce a CVPixelBuffer from that buffer
        var pixelBuffer: CVPixelBuffer?
        rgb.withUnsafeMutableBytes { (pointer: UnsafeMutableRawBufferPointer) in
            if let rawPointer = pointer.baseAddress {
                let ret = CVPixelBufferCreateWithBytes(
                    kCFAllocatorDefault,
                    width,
                    height,
                    kCVPixelFormatType_32ARGB,
                    rawPointer,
                    width * 4,
                    nil,
                    nil,
                    nil,
                    &pixelBuffer
                )
                if ret != kCVReturnSuccess {
                    print("[CVPixelBuffer] Error: Unable to create pixel buffer from RGB332 image (error code = \(ret))")
                }
            }
        }
        return pixelBuffer
    }
}
