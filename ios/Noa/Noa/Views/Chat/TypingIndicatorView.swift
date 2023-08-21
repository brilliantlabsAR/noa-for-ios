//
//  TypingIndicatorView.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/3/23.
//
//  Taken from: https://gist.github.com/Inncoder/17d6a89ad77f4ae82d31347465868010
//

import SwiftUI

struct TypingIndicatorView: View {
    @State private var _animatingDotIdx = 3

    private let _dotSize: CGFloat = 10
    private let _speed: Double = 0.3
    private let _staticColor: Color
    private let _animatingColor: Color

    public init(staticDotColor: Color, animatingDotColor: Color) {
        _staticColor = staticDotColor
        _animatingColor = animatingDotColor
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            ForEach(0..<3) { i in
                Capsule()
                    .foregroundColor((self._animatingDotIdx == i) ? self._animatingColor : self._staticColor)
                    .frame(width: self._dotSize, height: (self._animatingDotIdx == i) ? self._dotSize/3 : self._dotSize)
                    .animation(Animation.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.1).speed(2), value: _animatingDotIdx)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: self._speed, repeats: true) { _ in
                self._animatingDotIdx = TypingIndicatorView.selectNextDotRandomly(currentDotIdx: self._animatingDotIdx)
            }
        }
    }

    // Select next dot randomly without repeating current dot
    private static func selectNextDotRandomly(currentDotIdx: Int) -> Int {
        let allDots = [ 0, 1, 2 ]
        let candidateDots = allDots.filter { $0 != currentDotIdx }
        return candidateDots[Int.random(in: 0...1)]
    }
}

struct TypingIndicator_Previews: PreviewProvider {
    static var previews: some View {
        TypingIndicatorView(staticDotColor: Color(UIColor.lightGray), animatingDotColor: Color(UIColor.blue))
    }
}
