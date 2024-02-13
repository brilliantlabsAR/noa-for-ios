//
//  APIKeyPopupBoxView.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 7/10/23.
//

import SwiftUI

struct APIKeyPopupBoxView: View {
    @Binding public var scale: CGFloat
    @Binding public var popUpApiBox: Bool

    @EnvironmentObject private var _settings: Settings

    @State private var _openAIKey: String = ""
    @State private var _stabilityAIKey: String = ""

    var body: some View {
        VStack {
            Text("Enter API Keys")
                .font(.system(size: 20, weight: .semibold))
                .padding(.top, 20)
                .padding(.bottom, 2)

            Text("Your [OpenAI key](https://platform.openai.com) is required. An optional [Stability AI key](https://platform.stability.ai) is needed for image generation.")
                .font(.system(size: 15, weight: .regular))
                .multilineTextAlignment(.center)
                .padding(.bottom, 5)

            TextField("OpenAI: sk-...", text: $_openAIKey)
                .padding(.all, 2)
                .background(Color.gray.opacity(0.2))
                .padding(.horizontal)

            TextField("Stability AI (Optional): sk-...", text: $_stabilityAIKey)
                .padding(.all, 2)
                .background(Color.gray.opacity(0.2))
                .padding(.horizontal)

            Divider().background(Color.gray)

            Button(action: {
                _settings.setOpenAIKey(_openAIKey)
                _settings.setStabilityAIKey(_stabilityAIKey)
                closeWithAnimation()
            }) {
                Text("Done")
                    .bold()
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 40)
        }
        .frame(width: 300)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(20)
        .shadow(radius: 20)
        .scaleEffect(max(scale, 1e-3))  // avoid singular matrix when scale hits 0
        .onAppear {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.scale = 1
            }

            // Fetch existing API key
            _openAIKey = _settings.openAIKey
            _stabilityAIKey = _settings.stabilityAIKey
        }
    }

    func closeWithAnimation() {
        withAnimation(.easeInOut(duration: 0.2)) {
            self.scale = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.popUpApiBox.toggle()
            }
        }
    }
}
