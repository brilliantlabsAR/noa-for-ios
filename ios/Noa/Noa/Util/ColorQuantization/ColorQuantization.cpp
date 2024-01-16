//
//  ColorQuantization.cpp
//  Noa
//
//  Created by Bart Trzynadlowski on 1/15/24.
//

#include "ColorQuantization.hpp"
#include <algorithm>
#include <cstdio>
#include <tuple>
#include <vector>

enum ColorChannel
{
    Red,
    Green,
    Blue
};

#pragma pack(push, 1)
struct Pixel
{
    uint16_t x;
    uint16_t y;
    uint8_t r;
    uint8_t g;
    uint8_t b;
    uint8_t _padding;

    Pixel()
    {
    }

    Pixel(uint16_t x, uint16_t y, const uint8_t *pixels, size_t stride, OSType format)
    {
        this->x = x;
        this->y = y;

        switch (format)
        {
        case kCVPixelFormatType_32ABGR:
            r = pixels[y * stride + x * 4 + 3];
            g = pixels[y * stride + x * 4 + 2];
            b = pixels[y * stride + x * 4 + 1];
            break;
        case kCVPixelFormatType_32ARGB:
            r = pixels[y * stride + x * 4 + 1];
            g = pixels[y * stride + x * 4 + 2];
            b = pixels[y * stride + x * 4 + 3];
            break;
        default:
            puts("[ColorQuantization]: Invalid pixel format passed to Pixel()");
            break;
        }
    }

    static inline bool compareRedChannel(const Pixel &pixel1, const Pixel &pixel2)
    {
        return pixel1.r < pixel2.r;
    }

    static inline bool compareGreenChannel(const Pixel &pixel1, const Pixel &pixel2)
    {
        return pixel1.g < pixel2.g;
    }

    static inline bool compareBlueChannel(const Pixel &pixel1, const Pixel &pixel2)
    {
        return pixel1.b < pixel2.b;
    }
};
#pragma pack(pop, 1)

std::pair<size_t, ColorChannel> findBucketWithLargestColorRange(const std::vector<std::vector<Pixel>> &buckets)
{
    size_t bestBucketIdx = 0;
    uint8_t bestRange = 0;
    ColorChannel bestChannel = Red;

    for (size_t i = 0; i < buckets.size(); i++)
    {
        const std::vector<Pixel> &pixels = buckets[i];
        if (0 == pixels.size())
        {
            continue;
        }

        uint8_t minR = 255;
        uint8_t maxR = 0;
        uint8_t minG = 255;
        uint8_t maxG = 0;
        uint8_t minB = 255;
        uint8_t maxB = 0;

        for (size_t j = 0; j < pixels.size(); j++)
        {
            minR = std::min(minR, pixels[j].r);
            maxR = std::max(maxR, pixels[j].r);
            minG = std::min(minG, pixels[j].g);
            maxG = std::max(maxG, pixels[j].g);
            minB = std::min(minB, pixels[j].b);
            maxB = std::max(maxB, pixels[j].b);
        }

        uint8_t rangeR = maxR - minR;
        uint8_t rangeG = maxG - minG;
        uint8_t rangeB = maxB - minB;

        if (rangeR > rangeG && rangeR > rangeB)
        {
            if (rangeR > bestRange)
            {
                bestBucketIdx = i;
                bestRange = rangeR;
                bestChannel = Red;
            }
        }
        else if (rangeG > rangeR && rangeG > rangeB)
        {
            if (rangeG > bestRange)
            {
                bestBucketIdx = i;
                bestRange = rangeG;
                bestChannel = Green;
            }
        }
        else
        {
            if (rangeB > bestRange)
            {
                bestBucketIdx = i;
                bestRange = rangeB;
                bestChannel = Blue;
            }
        }
    }

    return std::pair(bestBucketIdx, bestChannel);
}

void sortBucketByColorChannel(std::vector<Pixel> &bucket, ColorChannel channel)
{
    switch (channel)
    {
    case Red:
        std::sort(bucket.begin(), bucket.end(), Pixel::compareRedChannel);
        break;
    case Green:
        std::sort(bucket.begin(), bucket.end(), Pixel::compareGreenChannel);
        break;
    case Blue:
        std::sort(bucket.begin(), bucket.end(), Pixel::compareBlueChannel);
        break;
    }
}

std::pair<std::vector<PaletteValue>, std::vector<uint8_t>> quantizeColors(CVPixelBufferRef pixelBuffer, size_t numColors)
{
    assert(numColors <= 256);   // for now, we output to an 8-bit buffer

    CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(0));
    size_t byteStride = CVPixelBufferGetBytesPerRow(pixelBuffer);
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    OSType format = CVPixelBufferGetPixelFormatType(pixelBuffer);
    
    if (format != kCVPixelFormatType_32ABGR && format != kCVPixelFormatType_32ARGB)
    {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(0));
        puts("[ColorQuantization] Error: Pixel buffer must be ARGB or ABGR format");
        return std::pair(std::vector<PaletteValue>(), std::vector<uint8_t>());
    }
    
    uint8_t *bytes = reinterpret_cast<uint8_t *>(CVPixelBufferGetBaseAddress(pixelBuffer));
    if (nullptr == bytes)
    {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(0));
        puts("[ColorQuantization] Error: Unable to get buffer base address");
        return std::pair(std::vector<PaletteValue>(), std::vector<uint8_t>());
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(0));

    std::vector<PaletteValue> palette(numColors);
    std::vector<uint8_t> outputPixels(width * height);

    // Populate initial bucket with all pixels
    std::vector<std::vector<Pixel>> buckets;
    buckets.reserve(numColors); // reserve space so we can take references to buckets and still add to vector
    buckets.emplace_back(std::vector<Pixel>(width * height));
    size_t pixelIdx = 0;
    for (size_t y = 0; y < height; y++)
    {
        for (size_t x = 0; x < width; x++)
        {
            buckets[0][pixelIdx++] = Pixel(x, y, bytes, byteStride, format);
        }
    }

    // Median cut algorithm
    while (buckets.size() != numColors)
    {
        // Find the bucket that has the largest range in any color channel
        size_t bucketIdx;
        ColorChannel channel;
        std::tie(bucketIdx, channel) = findBucketWithLargestColorRange(buckets);
        std::vector<Pixel> &bucket = buckets[bucketIdx];
        if (bucket.size() < 2)
        {
            break;
        }

        // Sort that bucket by the color channel with the largest range
        sortBucketByColorChannel(bucket, channel);

        // Create a new bucket by splitting the current bucket and dumping half of its pixels
        // into it. Note that here we resize buckets but continue to use the bucket reference.
        // This only works because we reserved numColors elements in buckets so that adding to
        // it (up to that amount) does not cause any re-allocation (which would invalidate the
        // reference).
        size_t midwayIdx = bucket.size() / 2;
        buckets.emplace_back(std::vector<Pixel>(bucket.begin() + midwayIdx, bucket.end())); // upper half of current bucket into new one
        bucket.resize(midwayIdx);   // removes upper half from current bucket
    }

    // For each bucket, compute average color and write to output pixel buffer
    for (size_t colorIdx = 0; colorIdx < buckets.size(); colorIdx++)
    {
        std::vector<Pixel> &bucket = buckets[colorIdx];

        // Compute mean RGB for bucket
        uint32_t r = 0;
        uint32_t g = 0;
        uint32_t b = 0;
        for (const Pixel &pixel: bucket)
        {
            r += pixel.r;
            g += pixel.g;
            b += pixel.b;
        }
        r /= bucket.size();
        g /= bucket.size();
        b /= bucket.size();

        // Store in palette
        palette[colorIdx] = { .r = uint8_t(r), .g = uint8_t(g), .b = uint8_t(b) };

        // Write back palettized pixels
        for (Pixel &pixel: bucket)
        {
            outputPixels[pixel.y * width + pixel.x] = uint8_t(colorIdx);
        }
    }

    return std::pair(palette, outputPixels);
}

void applyColorsToPixelBuffer(CVPixelBufferRef pixelBuffer, const std::vector<PaletteValue> &palette, const std::vector<uint8_t> &pixels)
{
    CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(0));
    size_t byteStride = CVPixelBufferGetBytesPerRow(pixelBuffer);
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    OSType format = CVPixelBufferGetPixelFormatType(pixelBuffer);

    uint8_t *bytes = reinterpret_cast<uint8_t *>(CVPixelBufferGetBaseAddress(pixelBuffer));
    if (nullptr == bytes)
    {
        puts("[ColorQuantization] Error: Unable to get buffer base address");
        goto exit;
    }

    if (format != kCVPixelFormatType_32ABGR && format != kCVPixelFormatType_32ARGB)
    {
        puts("[ColorQuantization] Error: Pixel buffer must be ARGB or ABGR format");
        goto exit;
    }
    
    if (width * height != pixels.size())
    {
        puts("[ColorQuantization] Error: Source and destination pixel buffers must have same number of pixels");
        goto exit;
    }

    switch (format)
    {
    case kCVPixelFormatType_32ABGR:
        for (size_t y = 0; y < height; y++)
        {
            for (size_t x = 0; x < width; x++)
            {
                uint8_t colorIdx = pixels[y * width + x];
                PaletteValue color = palette[colorIdx];
                bytes[y * byteStride + x * 4 + 3] = color.r;
                bytes[y * byteStride + x * 4 + 2] = color.g;
                bytes[y * byteStride + x * 4 + 1] = color.b;
            }
        }
        break;
    case kCVPixelFormatType_32ARGB:
        for (size_t y = 0; y < height; y++)
        {
            for (size_t x = 0; x < width; x++)
            {
                uint8_t colorIdx = pixels[y * width + x];
                PaletteValue color = palette[colorIdx];
                bytes[y * byteStride + x * 4 + 1] = color.r;
                bytes[y * byteStride + x * 4 + 2] = color.g;
                bytes[y * byteStride + x * 4 + 3] = color.b;
            }
        }
        break;
    default:
        puts("[ColorQuantization]: Invalid pixel format");
        break;
    }

exit:
    CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(0));
}
