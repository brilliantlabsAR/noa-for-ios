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

void quantizeColors(CVPixelBufferRef pixelBuffer, size_t colors);

#endif /* ColorQuantization_hpp */
