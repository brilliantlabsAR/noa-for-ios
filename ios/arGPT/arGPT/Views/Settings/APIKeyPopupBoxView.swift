//
//  APIKeyPopupBoxView.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 7/10/23.
//

import SwiftUI

struct APIKeyPopupBoxView: View {
    @Binding public var scale: CGFloat
    @Binding public var popUpApiBox: Bool

    @EnvironmentObject private var _settings: Settings

    @State private var _apiKey: String = ""

    var body: some View {
        VStack {
            Text("Enter your OpenAI API key")
                .font(.system(size: 20, weight: .semibold))
                .padding(.top, 20)
                .padding(.bottom, 2)

            Text("If you don’t have a key, press \"Get Key\" to be taken to OpenAI.")
                .font(.system(size: 15, weight: .regular))
                .multilineTextAlignment(.center)
                .padding(.bottom, 5)

            TextField("sk-...", text: $_apiKey)
                .padding(.all, 2)
                .background(Color.gray.opacity(0.2))
                .padding(.horizontal)

            Divider().background(Color.gray)

            HStack {
                Button(action: {
                    _settings.setAPIKey(_apiKey)
                    closeWithAnimation()
                }) {
                    Text("Done")
                        .bold()
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                }

                Divider()
                    .background(Color.gray)
                    .padding(.top, -8)

                Button(action: {
                    UIApplication.shared.open(URL(string: "http://platform.openai.com")!)
                }) {
                    Text("Get Key")
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                }
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
            _apiKey = _settings.apiKey
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
