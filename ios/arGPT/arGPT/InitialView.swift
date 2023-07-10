//
//  InitialView.swift
//  arGPT
//
//  Created by Artur Burlakin on 6/29/23.
//
//  Resources
//  ---------
//  - "Computed State in SwiftUI view"
//    https://yoswift.dev/swiftui/computed-state/
//

import SwiftUI

struct InitialView: View {
    @Binding private var _pairedMonocleID: UUID?

    private var _showPairingSheet: Binding<Bool> {
        Binding(
            get: { self._pairedMonocleID == nil },
            set: { (_: Bool) in /* do nothing */}
        )
    }

    var body: some View {
        ZStack {
            VStack {
                VStack {
                    Image("BrilliantLabsLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 12)
                        .position(x: 200, y: -10)
                    Text("arGPT")
                        .font(.system(size: 32, weight: .bold))
                        .position(x: 203,y:-77)
                    
                    Text("Let’s pair your device. Take your Monocle out of the case and bring it close.")
                        .font(.system(size: 17))
                        .multilineTextAlignment(.center)
                        .frame(width: 346, height: 87)
                        .position(x: 200, y: -60)
                }
                .frame(width: 393, height: 351)
                VStack {
                    RoundedRectangle(cornerRadius: 25)
                        .fill(Color.white)
                        .frame(width: 370, height: 370)
                        .sheet(isPresented: _showPairingSheet) {
                            PairingSheetView()
                                .presentationDragIndicator(.hidden)
                                .presentationDetents([.height(370)])
                                
                        }
                }
            }
        }
    }

    init(pairedMonocleID: Binding<UUID?>) {
        __pairedMonocleID = pairedMonocleID
    }
}

struct PairingSheetView: View {
    var body: some View {
        let buttonName = "Searching"
        
        VStack {
            Text("Bring your device close.")
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
                .frame(width: 306, height: 29)
            
            Image("Monocle")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 306, height: 160)
            
            Button(action: {
                // No Action needed
            }) {
                Text(buttonName)
                    .font(.system(size: 22, weight: .medium))
            }
            .padding(EdgeInsets(top: 20, leading: 40, bottom: 20, trailing: 40))
            .padding(.horizontal, 60)
            .background(Color(red: 242/255, green: 242/255, blue: 247/255))
            .foregroundColor(Color(red: 142/255, green: 142/255, blue: 147/255))
            .cornerRadius(15)
        }
    }
}
struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        InitialView(pairedMonocleID: .constant(UUID()))
    }
}
