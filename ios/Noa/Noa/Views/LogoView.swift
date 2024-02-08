//
//  LogoView.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 2/7/24.
//

import SwiftUI

struct LogoView: View {
    var body: some View {
        let light = Image("BrilliantLabsLogo")
            .resizable()
        let dark = Image("BrilliantLabsLogo_Dark")
            .resizable()
        ColorModeAdaptiveImage(light: light, dark: dark)
            .aspectRatio(contentMode: .fit)
            .frame(width: 100, height: 12)
            .padding(.top, 80)

        Text("Noa")
            .font(.system(size: 32, weight: .bold))
            .padding(.top, -7)
    }
}

#Preview {
    LogoView()
}
