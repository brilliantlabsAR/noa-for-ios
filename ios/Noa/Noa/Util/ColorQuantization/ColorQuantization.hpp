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
};

std::pair<std::vector<PaletteValue>, std::vector<uint8_t>> quantizeColors(CVPixelBufferRef pixelBuffer, size_t colors);
void applyColorsToPixelBuffer(CVPixelBufferRef pixelBuffer, const std::vector<PaletteValue> &palette, const std::vector<uint8_t> &pixels);

#endif /* ColorQuantization_hpp */
