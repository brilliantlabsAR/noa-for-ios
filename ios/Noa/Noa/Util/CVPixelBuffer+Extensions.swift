//
//  CVPixelBuffer+Extensions.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 8/28/23.
//

import CoreVideo

extension CVPixelBuffer {
    public func clearAlpha() {
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
}
