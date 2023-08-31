//
//  UIImage+Extensions.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 8/25/23.
//

import UIKit
import CoreVideo
import VideoToolbox

extension UIImage {
    /// Creates a `UIImage` from a `CVPixelBuffer`. Not all `CVPixelBuffer` formats are supported.
    /// - Parameter pixelBuffer: The pixel buffer to create the image from.
    /// - Returns: `nil` if unsuccessful, otherwise `UIImage`.
    public convenience init?(pixelBuffer: CVPixelBuffer) {
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        guard let cgImage = cgImage else {
            print("[UIImage] Unable to create UIImage from pixel buffer")
            return nil
        }
        self.init(cgImage: cgImage)
    }

    public func centerCropped(to cropSize: CGSize) -> UIImage? {
        guard let srcImage = self.cgImage else {
            print("[UIImage] Unable to obtain CGImage")
            return nil
        }

        // Must be careful to avoid rounding up anywhere!
        let xOffset = (size.width - cropSize.width) / 2.0
        let yOffset = (size.height - cropSize.height) / 2.0
        let cropRect = CGRect(x: CGFloat(Int(xOffset)), y: CGFloat(Int(yOffset)), width: CGFloat(Int(cropSize.width)), height: CGFloat(Int(cropSize.height)))

        guard let croppedImage = srcImage.cropping(to: cropRect) else {
            print("[UIImage] Failed to produce cropped CGImage")
            return nil
        }

        return UIImage(cgImage: croppedImage, scale: self.imageRendererFormat.scale, orientation: self.imageOrientation)
    }

    public func expandImageWithLetterbox(to newSize: CGSize) -> UIImage? {
        assert(newSize.width >= self.size.width && newSize.height >= self.size.height, "Image can only be expanded")

        if newSize == self.size {
            return self
        }

        UIGraphicsBeginImageContext(newSize)
        defer {
            UIGraphicsEndImageContext()
        }
        guard let ctx = UIGraphicsGetCurrentContext() else {
            print("[UIImage] Unable to get current graphics context")
            return nil
        }

        // Fill new image with black and then draw old image in the middle
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill([ CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height) ])
        let xOffset = (newSize.width - self.size.width) / 2
        let yOffset = (newSize.height - self.size.height) / 2
        self.draw(in: CGRect(x: xOffset, y: yOffset, width: self.size.width, height: self.size.height))

        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        return newImage
    }

    /// Converts a `UIImage` to an ARGB-formatted `CVPixelBuffer`. The `UIImage` is assumed to be
    /// opaque and the alpha channel is ignored. The resulting pixel buffer has all alpha values set to `0xFF`.
    /// - Returns: `CVPixelBuffer` if successful otherwise `nil`.
    public func toPixelBuffer() -> CVPixelBuffer? {
        let width = Int(size.width)
        let height = Int(size.height)

        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary

        var pixelBuffer: CVPixelBuffer?

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            attributes,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess,
              let pixelBuffer = pixelBuffer else {
            print("[UIImage] Error: Unable to create pixel buffer")
            return nil
        }

        let lockFlags = CVPixelBufferLockFlags(rawValue: 0)

        guard CVPixelBufferLockBaseAddress(pixelBuffer, lockFlags) == kCVReturnSuccess else {
            print("[UIImage] Error: Unable to lock pixel buffer")
            return nil
        }

        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, lockFlags)
            print("[UIImage] Error: Unable to create CGContext")
            return nil
        }

        UIGraphicsPushContext(ctx)
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()

        return pixelBuffer
    }
}
