//
//  ColorQuantization.hpp
//  Noa
//
//  Created by Bart Trzynadlowski on 1/15/24.
//

#ifndef ColorQuantization_hpp
#define ColorQuantization_hpp

#include <CoreVideo/CVPixelBuffer.h>
#include <cstdint>
#include <tuple>
#include <vector>

struct PaletteValue
{
    uint8_t r;
    uint8_t g;
    uint8_t b;

    /// Perceived luminance according to ITU BT.601.
    float luminance() const
    {
        // See: http://www.itu.int/rec/R-REC-BT.601 and https://stackoverflow.com/questions/596216/formula-to-determine-perceived-brightness-of-rgb-color
        return 0.299f * (float(r) / 255.0f) + 0.587f * (float(g) / 255.0f) + 0.114f * (float(b) / 255.0f);
    }
};

std::pair<std::vector<PaletteValue>, std::vector<uint8_t>> quantizeColors(CVPixelBufferRef pixelBuffer, size_t colors, size_t outputBitDepth);

/// Finds the darkest color in the palette, makes it black, and maps it to color 0, adjusting all image pixels.
void setDarkestColorToBlackAndIndex0(std::vector<PaletteValue> &palette, std::vector<uint8_t> &pixels, size_t bitDepth);

void applyColorsToPixelBuffer(CVPixelBufferRef pixelBuffer, const std::vector<PaletteValue> &palette, const std::vector<uint8_t> &pixels, size_t bitDepth);

#endif /* ColorQuantization_hpp */
