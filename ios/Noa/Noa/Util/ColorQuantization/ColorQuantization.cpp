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
    R,
    G,
    B
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

    void write(uint8_t r, uint8_t g, uint8_t b, uint8_t *pixels, size_t stride, OSType format)
    {
        switch (format)
        {
        case kCVPixelFormatType_32ABGR:
            pixels[size_t(y) * stride + x * 4 + 3] = r;
            pixels[size_t(y) * stride + x * 4 + 2] = g;
            pixels[size_t(y) * stride + x * 4 + 1] = b;
            break;
        case kCVPixelFormatType_32ARGB:
            pixels[size_t(y) * stride + size_t(x) * 4 + 1] = r;
            pixels[size_t(y) * stride + size_t(x) * 4 + 2] = g;
            pixels[size_t(y) * stride + size_t(x) * 4 + 3] = b;
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
    ColorChannel bestChannel = R;

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
                bestChannel = R;
            }
        }
        else if (rangeG > rangeR && rangeG > rangeB)
        {
            if (rangeG > bestRange)
            {
                bestBucketIdx = i;
                bestRange = rangeG;
                bestChannel = G;
            }
        }
        else
        {
            if (rangeB > bestRange)
            {
                bestBucketIdx = i;
                bestRange = rangeB;
                bestChannel = B;
            }
        }
    }

    return std::pair(bestBucketIdx, bestChannel);
}

void sortBucketByColorChannel(std::vector<Pixel> &bucket, ColorChannel channel)
{
    switch (channel)
    {
    case R:
        std::sort(bucket.begin(), bucket.end(), Pixel::compareRedChannel);
        break;
    case G:
        std::sort(bucket.begin(), bucket.end(), Pixel::compareGreenChannel);
        break;
    case B:
        std::sort(bucket.begin(), bucket.end(), Pixel::compareBlueChannel);
        break;
    }
}

void quantizeColors(CVPixelBufferRef pixelBuffer, size_t numColors)
{
    OSType format = CVPixelBufferGetPixelFormatType(pixelBuffer);
    if (format != kCVPixelFormatType_32ABGR && format != kCVPixelFormatType_32ARGB)
    {
        puts("[ColorQuantization] Error: Pixel buffer must be ARGB or ABGR format");
        return;
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(0));
    size_t byteStride = CVPixelBufferGetBytesPerRow(pixelBuffer);
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    uint8_t *bytes = reinterpret_cast<uint8_t *>(CVPixelBufferGetBaseAddress(pixelBuffer));
    if (nullptr == bytes)
    {
        puts("[ColorQuantization] Error: Unable to get buffer base address");
        goto exit;
    }

    {
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

        // For each bucket, compute average color and write back to pixel buffer
        for (std::vector<Pixel> &bucket: buckets)
        {
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

            // Write back mean RGB for every pixel
            for (Pixel &pixel: bucket)
            {
                pixel.write(r, g, b, bytes, byteStride, format);
            }
        }
    }

exit:
    CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(0));
}
