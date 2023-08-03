//
//  UpdateSheetView.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 7/23/23.
//

import SwiftUI

struct UpdateSheetView: View {
    @Binding var updateProgressPercent: Int
    
    //Video logic
    @State private var triggerUpdate = false
    let videoURL = Bundle.main.url(forResource: "SpinningMonocle", withExtension: "mp4")!
    
    var body: some View {
        let buttonName = "Keep the app open"
        HStack {
            Spacer()
        }
        VStack {
            Text("Updating Software \(updateProgressPercent)%")
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.bottom)
//            Image("Monocle")
//                .resizable()
//                .aspectRatio(contentMode: .fit)
//                .frame(width: 306, height: 160)
//                .padding()
            LoopingVideoPlayer(videoURL: videoURL)
                .frame(width: 150, height: 150)
                .onAppear {
                    triggerUpdate.toggle()
                }
                .id(triggerUpdate) // This will re-create the LoopingVideoPlayer on update
            
            Button(action: {
                // No Action needed
            }) {
                Text(buttonName)
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: 306, height: 50)
            }
            //          .padding(EdgeInsets(top: 20, leading: 40, bottom: 20, trailing: 40))
            //          .padding(.horizontal, 60)
            .background(Color(red: 242/255, green: 242/255, blue: 247/255))
            .foregroundColor(Color(red: 141/255, green: 141/255, blue: 147/255))
            .cornerRadius(15)
        }
    }



    init(updateProgressPercent: Binding<Int>) {
        self._updateProgressPercent = updateProgressPercent
    }
}
