//
//  SplashScreenView.swift
//  a eye
//
//  Created by Raj Nakarja on 2023-03-29.
//

import SwiftUI

struct SplashScreenView: View {
    @State private var isActive = false
    @State private var opacity = 0.0
    
    var body: some View {
        if isActive {
            ContentView()
                .colorScheme(.light)
        }
        else {
            ZStack{
                Color(.white)
                    .ignoresSafeArea()
                ZStack{
                    VStack{
                        Spacer()
                        HStack{
                            Spacer()
                            Image("SplashImage")
                                .resizable()
                                .frame(width: 400, height: 400)
                        }
                    }
                    .ignoresSafeArea()
                    VStack{
                        Text("a eye")
                            .font(.title)
                            .fontWeight(.medium)
                            .foregroundColor(Color.black)
                            .offset(y: 50)
                        Text("for Monocle & Frame")
                            .foregroundColor(Color.black)
                            .offset(y: 50)
                        Spacer()
                        Text("> brilliant(labs)")
                            .foregroundColor(Color.black)
                    }
                }
                
                .opacity(opacity)
                .onAppear(){
                    withAnimation(.easeIn(duration: 1.2)){
                        self.opacity = 1.0
                    }
                }
            }
            .onAppear(){
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0){
                    withAnimation {
                        self.isActive = true
                    }
                }
            }
        }
        
    }
}

struct SplashScreenView_Previews: PreviewProvider {
    static var previews: some View {
        SplashScreenView()
    }
}
