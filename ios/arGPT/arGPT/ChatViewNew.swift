//
//  ChatViewNew.swift
//  arGPT
//
//  Created by Artur Burlakin on 2023-06-30.
//

import SwiftUI

struct ChatViewNew: View {
    @State private var popUpApiBox: Bool = false
    @State private var scale: CGFloat = 0

    var body: some View {
        ZStack {
            VStack {
                HStack {
                    Spacer()
                        .frame(width: 70)
                    
                    Text("arGPT")
                        .font(.system(size: 22, weight: .bold))
                        .frame(maxWidth: .infinity)
                    
                    Button(action: {}) {
                        Menu {
                            Button(action: {
                                self.popUpApiBox.toggle()
                            }) {
                                Label("Change API Key", systemImage: "person.circle")
                            }
                            Button(action: {
                                
                                
                            }) {
                                Label("Unpair Monocle", systemImage: "person.circle")
                                    .foregroundColor(Color.red)
                            }
                        }
                        
                        label: {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(Color(red: 87/255, green: 199/255, blue: 170/255))
                        }
                    }
                    .padding()
                }
                Spacer()
            }

            if popUpApiBox {
                Rectangle()
                    .fill(Color.black.opacity(0.4))
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.scale = 0.5
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                self.scale = 0.5
                                self.popUpApiBox = false
                            }
                        }
                    }

                ApiBox(scale: $scale, popUpApiBox: $popUpApiBox)
            }
        }
    }
}

struct ApiBox: View {
    
    @Binding var scale: CGFloat
    @Binding var popUpApiBox: Bool
    @State private var apiCode: String = ""

    var body: some View {
        VStack {
            Text("Enter your OpenAI API key")
                .font(.system(size: 20, weight: .semibold))
                .padding(.top, 20)
                .padding(.bottom, 2)
            
            Text("If you don’t have a key, visit platform.openai.com to create one.")
                .font(.system(size: 15, weight: .regular))
                .multilineTextAlignment(.center)
                .padding(.bottom, 5)

            TextField("sk-...", text: $apiCode)
                .padding(.all, 2)
                .background(Color.gray.opacity(0.2))
                .padding(.horizontal)
            
            Divider().background(Color.gray)
            
            HStack {
                Button(action: {
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
                    closeWithAnimation()
                }) {
                    Text("Close")
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 40)
        }
        .frame(width: 300)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(radius: 20)
        .scaleEffect(scale)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.scale = 1
            }
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


struct ChatViewNew_Previews: PreviewProvider {
    static var previews: some View {
        ChatViewNew()
    }
}
