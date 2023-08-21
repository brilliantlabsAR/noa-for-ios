//
//  ColorModeAdaptiveImage.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 7/11/23.
//

import SwiftUI

struct ColorModeAdaptiveImage: View {
    @Environment(\.colorScheme) var colorScheme
    let light: Image
    let dark: Image

    var body: some View {
        colorScheme == .light ? light : dark
    }
}

struct ColorModeAdaptiveImage_Previews: PreviewProvider {
    static var previews: some View {
        ColorModeAdaptiveImage(light: Image("BrilliantLabsLogo"), dark: Image("BrilliantLabsLogo_Dark"))
    }
}
