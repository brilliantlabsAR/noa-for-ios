//
//  ColorQuantization.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 1/3/24.
//

import CoreVideo

/// Pixel color and its position within the image
private struct Pixel {
    let r: UInt8    // channel 0
    let g: UInt8    // channel 1
    let b: UInt8    // channel 2
    let x: UInt16
    let y: UInt16

    init() {
        r = 0
        g = 0
        b = 0
        x = 0
        y = 0
    }

    init(x: Int, y: Int, pixels: UnsafeMutablePointer<UInt8>, stride: Int, format: OSType) {
        self.x = UInt16(x)
        self.y = UInt16(y)
        switch format {
        case kCVPixelFormatType_32ABGR:
            r = pixels[y * stride + x + 3]
            b = pixels[y * stride + x + 2]
            g = pixels[y * stride + x + 1]
        case kCVPixelFormatType_32ARGB:
            r = pixels[y * stride + x + 1]
            b = pixels[y * stride + x + 2]
            g = pixels[y * stride + x + 3]
        default:
            fatalError("Invalid pixel format in quantizeColors()")
        }
    }
}

func quantizeColors(pixelBuffer: CVPixelBuffer, colors: Int) -> Data? {
    let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
    guard format == kCVPixelFormatType_32ABGR || format == kCVPixelFormatType_32ARGB else {
        print("[ColorQuantization] Error: Pixel buffer must be ARGB or ABGR format")
        return nil
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
    defer {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
    }
    let byteStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let offsetToNextLine = byteStride - width * 4
    guard let address = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        print("[ColorQuantization] Error: Unable to get buffer base address")
        return nil
    }
    let bytes = address.assumingMemoryBound(to: UInt8.self)

    // Populate initial bucket with pixels
    var buckets: [[Pixel]] = [ Array(repeating: Pixel(), count: width * height) ]
    var pixelIdx = 0
    for y in 0..<height {
        for x in 0..<width {
            buckets[0][pixelIdx] = Pixel(x: x, y: y, pixels: bytes, stride: byteStride, format: format)
            pixelIdx += 1
        }
    }

    // Median cut algorithm
    while true {
        if let (idx, channel) = bucketWithHighestColorVariation(&buckets) {
            // Sort bucket with largest range in any color channel by that color channel
            buckets[idx].sort(by: { $0[keyPath: channel] < $1[keyPath: channel] })

            // Dump half into a new bucket
            if buckets[idx].count < 2 {
                break
            }
            let halfIdx = buckets[idx].count / 2
            var newBucket: [Pixel] = []
            for i in 0..<halfIdx {
                // Take from back side of old bucket and put into new
                newBucket.append(buckets[idx][buckets[idx].count - 1 - i])
            }
            buckets[idx].removeLast(halfIdx)
            buckets.append(newBucket)

            // Stop when we have the required number of buckets
            if buckets.count == colors {
                break
            }
        }
    }

    // Number of buckets
    print("Buckets = \(buckets.count)")
    print("Total pixels: \(height * width)")
    for i in 0..<16 {
        print("Bucket[\(i)] = \(buckets[i].count) pixels")
    }


    


    return nil
}

private func bucketWithHighestColorVariation(_ buckets: inout [[Pixel]]) -> (Int, KeyPath<Pixel, UInt8>)? {
    // Compute rangs for each color channel in each bucket
    var ranges: [(Int, KeyPath<Pixel, UInt8>, UInt8)] = []    // (bucket idx, color channel, range)
    for i in 0..<buckets.count {
        for channel in [ \Pixel.r, \Pixel.g, \Pixel.b ] {
            guard let min = buckets[i].map({ $0[keyPath: channel] }).min(),
                  let max = buckets[i].map({ $0[keyPath: channel] }).max() else {
                continue
            }
            ranges.append((i, channel, max - min))
        }
    }

    // Get the largest
    guard let maxRange = ranges.sorted(by: { $0.2 > $1.2 }).first else {
        return nil
    }
    return (maxRange.0, maxRange.1)
}
