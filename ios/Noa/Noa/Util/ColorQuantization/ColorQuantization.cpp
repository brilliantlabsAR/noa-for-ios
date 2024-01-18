//
//  ColorQuantization.cpp
//  Noa
//
//  Created by Bart Trzynadlowski on 1/15/24.
//

#include "ColorQuantization.hpp"
#include <algorithm>
#include <cstdio>
#include <random>
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
    uint8_t k;

    Pixel()
    {
    }

    Pixel(uint16_t x, uint16_t y, const uint8_t *pixels, size_t stride, OSType format, uint8_t k = 0)
    {
        this->x = x;
        this->y = y;
        this->k = k;

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

std::pair<ColorChannel, uint8_t> findColorChannelWithLargestRange(const std::vector<Pixel> pixels)
{
    uint8_t minR = 255;
    uint8_t maxR = 0;
    uint8_t minG = 255;
    uint8_t maxG = 0;
    uint8_t minB = 255;
    uint8_t maxB = 0;

    for (size_t i = 0; i < pixels.size(); i++)
    {
        minR = std::min(minR, pixels[i].r);
        maxR = std::max(maxR, pixels[i].r);
        minG = std::min(minG, pixels[i].g);
        maxG = std::max(maxG, pixels[i].g);
        minB = std::min(minB, pixels[i].b);
        maxB = std::max(maxB, pixels[i].b);
    }

    uint8_t rangeR = maxR - minR;
    uint8_t rangeG = maxG - minG;
    uint8_t rangeB = maxB - minB;

    if (rangeR > rangeG && rangeR > rangeB)
    {
        return std::pair(Red, rangeR);
    }
    else if (rangeG > rangeR && rangeG > rangeB)
    {
        return std::pair(Green, rangeG);
    }
    return std::pair(Blue, rangeB);
}

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

        ColorChannel channel;
        uint8_t range;
        std::tie(channel, range) = findColorChannelWithLargestRange(pixels);
        if (range > bestRange)
        {
            bestBucketIdx = i;
            bestRange = range;
            bestChannel = channel;
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

std::pair<std::vector<PaletteValue>, std::vector<uint8_t>> quantizeColors(CVPixelBufferRef pixelBuffer, size_t numColors, size_t outputBitDepth)
{
    assert(numColors <= 16);    // for now, we output to a 4-bit buffer
    assert(outputBitDepth == 4);

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
    std::vector<uint8_t> outputPixels(width * height / 2);  // 4 bits per pixel

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
        // Recursively subdivide each bucket
        size_t initialBucketCount = buckets.size();
        for (size_t i = 0; i < initialBucketCount; i++)
        {
            std::vector<Pixel> &bucket = buckets[i];
            if (bucket.size() < 2)
            {
                goto exit_algo;
            }

            // Find color channel with largest range and sort by that channel
            ColorChannel channel;
            uint8_t range;
            std::tie(channel, range) = findColorChannelWithLargestRange(bucket);
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
    }
exit_algo:

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

        // Write back palettized pixels to 4-bit bitmap
        for (Pixel &pixel: bucket)
        {
            size_t pixelIdx = pixel.y * width + pixel.x;
            size_t byteIdx = pixelIdx / 2;
            size_t shiftAmount = (~pixelIdx & 1) * 4;   // even pixel in high nibble, odd in low
            uint8_t mask = 0xf0 >> shiftAmount;         // mask if reverse: mask off low nibble when writing high nibble, etc.
            outputPixels[byteIdx] = (outputPixels[byteIdx] & mask) | (colorIdx << shiftAmount);
        }
    }

    return std::pair(palette, outputPixels);
}

std::pair<std::vector<PaletteValue>, std::vector<uint8_t>> quantizeColorsKMeans(CVPixelBufferRef pixelBuffer, size_t numColors, size_t outputBitDepth)
{
    assert(numColors <= 16);    // for now, we output to a 4-bit buffer
    assert(outputBitDepth == 4);

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
    std::vector<uint8_t> outputPixels(width * height / 2);  // 4 bits per pixel

    // Random number generator for initial k-means clusters
    std::random_device dev;
    std::mt19937 rng(dev());
    std::uniform_int_distribution<std::mt19937::result_type> random(0, unsigned(numColors - 1));   // [0, numColors-1]

    // Array of labeled pixels, randomly assigned to initial clusters
    std::vector<Pixel> pixels(width * height);
    size_t pixelIdx = 0;
    for (size_t y = 0; y < height; y++)
    {
        for (size_t x = 0; x < width; x++)
        {
           pixels[pixelIdx++] = Pixel(x, y, bytes, byteStride, format, random(rng));
        }
    }

    // Centroid for each color cluster (mean RGB value)
    struct Color
    {
        uint64_t r = 0;
        uint64_t g = 0;
        uint64_t b = 0;
    };
    Color centroids[numColors];
    int numPixelsInCluster[numColors];

    // Repeat k-means until complete
    size_t maxIterations = 24;
    size_t iterations = 0;
    bool didChange = false;
    do {
        didChange = false;

        // Compute average for each cluster
        for (size_t i = 0; i < numColors; i++)
        {
            centroids[i] = Color(); // zero out
            numPixelsInCluster[i] = 0;
        }
        for (size_t i = 0; i < pixels.size(); i++)
        {
            size_t k = pixels[i].k;
            centroids[k].r += pixels[i].r;
            centroids[k].g += pixels[i].g;
            centroids[k].b += pixels[i].b;
            numPixelsInCluster[k]++;
        }
        for (size_t i = 0; i < numColors; i++)
        {
            centroids[i].r /= numPixelsInCluster[i];
            centroids[i].g /= numPixelsInCluster[i];
            centroids[i].b /= numPixelsInCluster[i];
        }

        // Assign each pixel to nearest cluster (cluster whose centroid is nearest)
        for (size_t i = 0; i < pixels.size(); i++)
        {
            // Compute distance^2 to each cluster centroid
            uint64_t distance[numColors];
            for (size_t j = 0; j < numColors; j++)
            {
                distance[j] = (centroids[j].r - pixels[i].r) * (centroids[j].r - pixels[i].r) +
                              (centroids[j].g - pixels[i].g) * (centroids[j].g - pixels[i].g) +
                              (centroids[j].b - pixels[i].b) * (centroids[j].b - pixels[i].b);
            }

            // Which is nearest?
            size_t bestK = 0;
            size_t nearestDistance = distance[0];
            for (size_t j = 1; j < numColors; j++)
            {
                if (distance[j] < nearestDistance)
                {
                    nearestDistance = distance[j];
                    bestK = j;
                }
            }

            // Did an assignment change?
            didChange |= pixels[i].k != bestK;

            // Assign
            pixels[i].k = bestK;
        }

        iterations++;
    } while (didChange && iterations < maxIterations);

    // Create palette
    for (size_t i = 0; i < numColors; i++)
    {
        palette[i] = { .r = uint8_t(centroids[i].r), .g = uint8_t(centroids[i].g), .b = uint8_t(centroids[i].b) };
    }

    // Assign colors to output pixels
    for (Pixel &pixel: pixels)
    {
        uint8_t colorIdx = pixel.k;                 // color is just the cluster index
        size_t pixelIdx = pixel.y * width + pixel.x;
        size_t byteIdx = pixelIdx / 2;
        size_t shiftAmount = (~pixelIdx & 1) * 4;   // even pixel in high nibble, odd in low
        uint8_t mask = 0xf0 >> shiftAmount;         // mask if reverse: mask off low nibble when writing high nibble, etc.
        outputPixels[byteIdx] = (outputPixels[byteIdx] & mask) | (colorIdx << shiftAmount);
    }

    return std::pair(palette, outputPixels);
}


void setDarkestColorToBlackAndIndex0(std::vector<PaletteValue> &palette, std::vector<uint8_t> &pixels, size_t bitDepth)
{
    assert(bitDepth == 4);

    // Find darkest color
    float darkestLuma = 1.0f;
    size_t darkestColor = 0;
    for (size_t i = 0; i < palette.size(); i++)
    {
        float luma = palette[i].luminance();
        if (luma < darkestLuma)
        {
            darkestLuma = luma;
            darkestColor = i;
        }
    }

    // Make darkest color fully black
    palette[darkestColor].r = 0;
    palette[darkestColor].g = 0;
    palette[darkestColor].b = 0;

    // Swap with color 0 so that color 0 is black
    if (0 == darkestColor)
    {
        return;
    }
    PaletteValue tmp = palette[0];
    palette[0] = palette[darkestColor];
    palette[darkestColor] = tmp;

    // Construct a LUT that swaps occurrences of 0 <-> darkestColor for each 4-bit pixel
    uint8_t lut[256];
    for (size_t i = 0; i < 256; i++)
    {
        lut[i] = i;
    }
    lut[0x00 | 0x00] = (darkestColor << 4) | darkestColor;  // (0, 0) -> (darkestColor, darkestColor)
    lut[0x00 | darkestColor] = (darkestColor << 4) | 0x00;  // (0, darkestColor) -> (darkestColor, 0)
    lut[(darkestColor << 4) | 0x00] = 0x00 | darkestColor;  // (darkestColor, 0) -> (0, darkestColor)
    lut[(darkestColor << 4) | darkestColor] = 0x00;         // (darkestColor, darkestColor) -> (0, 0)

    // Remap pixels using the LUT
    for (size_t i = 0; i < pixels.size(); i++)
    {
        pixels[i] = lut[pixels[i]];
    }
}

void applyColorsToPixelBuffer(CVPixelBufferRef pixelBuffer, const std::vector<PaletteValue> &palette, const std::vector<uint8_t> &pixels, size_t bitDepth)
{
    assert(bitDepth == 4);

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
    
    if (width * height != pixels.size() * 2)    // pixels is 4bpp
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
                size_t pixelIdx = y * width + x;
                size_t byteIdx = pixelIdx / 2;
                size_t shiftAmount = (~pixelIdx & 1) * 4;                   // even pixel in high nibble, odd in low
                uint8_t colorIdx = (pixels[byteIdx] >> shiftAmount) & 0xf;  // extract color value in nibble
                PaletteValue color = palette[colorIdx];
                bytes[y * byteStride + x * 4 + 0] = 0xff;
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
                size_t pixelIdx = y * width + x;
                size_t byteIdx = pixelIdx / 2;
                size_t shiftAmount = (~pixelIdx & 1) * 4;                   // even pixel in high nibble, odd in low
                uint8_t colorIdx = (pixels[byteIdx] >> shiftAmount) & 0xf;  // extract color value in nibble
                PaletteValue color = palette[colorIdx];
                bytes[y * byteStride + x * 4 + 0] = 0xff;
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
