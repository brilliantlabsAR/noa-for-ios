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
            r = pixels[y * stride + x * 4 + 3]
            g = pixels[y * stride + x * 4 + 2]
            b = pixels[y * stride + x * 4 + 1]
        case kCVPixelFormatType_32ARGB:
            r = pixels[y * stride + x * 4 + 1]
            g = pixels[y * stride + x * 4 + 2]
            b = pixels[y * stride + x * 4 + 3]
        default:
            fatalError("Invalid pixel format in quantizeColors()")
        }
    }

    func write(r: UInt8, g: UInt8, b: UInt8, pixels: UnsafeMutablePointer<UInt8>, stride: Int, format: OSType) {
        let x = Int(self.x)
        let y = Int(self.y)
        switch format {
        case kCVPixelFormatType_32ABGR:
            pixels[y * stride + x * 4 + 3] = r
            pixels[y * stride + x * 4 + 2] = g
            pixels[y * stride + x * 4 + 1] = b
        case kCVPixelFormatType_32ARGB:
            pixels[y * stride + x * 4 + 1] = r
            pixels[y * stride + x * 4 + 2] = g
            pixels[y * stride + x * 4 + 3] = b
        default:
            fatalError("Invalid pixel format in quantizeColors()")
        }
    }
}

func quantizeColors(pixelBuffer: CVPixelBuffer, colors: Int) -> CVPixelBuffer? {
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
    var stopwatch = Util.Stopwatch()
    while true {
        if let (idx, channel) = bucketWithHighestColorVariation(&buckets) {
            // Sort bucket with largest range in any color channel by that color channel
            stopwatch.start()
            buckets[idx].sort(by: { $0[keyPath: channel] < $1[keyPath: channel] })
            print("Bucket \(idx) Sort = \(stopwatch.elapsedMilliseconds())")

            // Dump half into a new bucket
            stopwatch.start()
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
            print("Bucket \(idx) Split = \(stopwatch.elapsedMilliseconds())")

            // Stop when we have the required number of buckets
            if buckets.count == colors {
                break
            }
        }
    }

    // Number of buckets
    print("Resolution = \(width) * \(height)")
    print("Buckets = \(buckets.count)")
    print("Total pixels: \(height * width)")
    var pixelCount = 0
    for i in 0..<16 {
        print("Bucket[\(i)] = \(buckets[i].count) pixels")
        pixelCount += buckets[i].count
    }
    print("Total pixels: \(pixelCount)")

    // Clear pixel buffer
//    memset(bytes, 0, byteStride * height)

    // For each bucket, compute average color and write back to pixel buffer
    var i = 0
    for bucket in buckets {
        print("Bucket \(i)")
        i += 1

        var r: Int = 0
        var g: Int = 0
        var b: Int = 0
        for pixel in bucket {
            r += Int(pixel.r)
            g += Int(pixel.g)
            b += Int(pixel.b)
        }
        r /= bucket.count
        g /= bucket.count
        b /= bucket.count

        for pixel in bucket {
            pixel.write(r: UInt8(r), g: UInt8(g), b: UInt8(b), pixels: bytes, stride: byteStride, format: format)
//            pixel.write(r: 0xff, g: 0xff, b: 0x00, pixels: bytes, stride: byteStride, format: format)
//            if pixel.x > 800 {
//                print("x,y=\(pixel.x), \(pixel.y) = \(r) \(g) \(b)")
//            }
        }
    }

    return pixelBuffer
}

private func bucketWithHighestColorVariation(_ buckets: inout [[Pixel]]) -> (Int, KeyPath<Pixel, UInt8>)? {
    var stopwatch = Util.Stopwatch()

    // Compute rangs for each color channel in each bucket
    var ranges: [(Int, KeyPath<Pixel, UInt8>, UInt8)] = []    // (bucket idx, color channel, range)
    for i in 0..<buckets.count {
        stopwatch.start()
//        for channel in [ \Pixel.r, \Pixel.g, \Pixel.b ] {
//            guard let min = buckets[i].map({ $0[keyPath: channel] }).min(),
//                  let max = buckets[i].map({ $0[keyPath: channel] }).max() else {
//                continue
//            }
//            ranges.append((i, channel, max - min))
//        }

        // Slightly faster
        if buckets[i].count == 0 {
            continue
        }

        var minR: UInt8 = 255
        var maxR: UInt8 = 0
        var minG: UInt8 = 255
        var maxG: UInt8 = 0
        var minB: UInt8 = 255
        var maxB: UInt8 = 0

        for j in 0..<buckets[i].count {
            minR = min(minR, buckets[i][j].r)
            maxR = max(maxR, buckets[i][j].r)
            minG = min(minG, buckets[i][j].g)
            maxG = max(maxG, buckets[i][j].g)
            minB = min(minB, buckets[i][j].b)
            maxB = max(maxB, buckets[i][j].b)
        }

        let rangeR = (Int(maxR) - Int(minR))
        let rangeG = (Int(maxG) - Int(minG))
        let rangeB = (Int(maxB) - Int(minB))
        if rangeR > rangeG && rangeR > rangeB {
            ranges.append((i, \Pixel.r, UInt8(rangeR)))
        } else if rangeG > rangeR && rangeG > rangeB {
            ranges.append((i, \Pixel.g, UInt8(rangeG)))
        } else {
            ranges.append((i, \Pixel.b, UInt8(rangeB)))
        }

        print("Bucket \(i) Range = \(stopwatch.elapsedMilliseconds()) ms")
    }

    // Get the largest
    stopwatch.start()
    guard let maxRange = ranges.sorted(by: { $0.2 > $1.2 }).first else {
        return nil
    }
    print("Highest Color Variation = \(stopwatch.elapsedMilliseconds())")
    return (maxRange.0, maxRange.1)
}
