import SwiftUI

struct MainView: View {
    @State private var settingPopup: Bool = false
    private var searchingButton = "Searching"
    
    var body: some View {
        ZStack {
            Color(red: 242/255, green: 242/255, blue: 247/255)
                .edgesIgnoringSafeArea(.all)
            VStack {
                VStack {
                    Button(action: {}) {
                        Menu {
                            Button(action: {
                                //Action here
                            }) {
                                Label("Change API Key", systemImage: "person.circle")
                            }
                            Button(action: {
                                //Action here
                            }) {
                                Label("Unpair Monocle", systemImage: "pencil.circle")
                                    .foregroundColor(Color(red: 255/255, green: 0/255, blue: 0/255))
                                
                            }
                        }
                    label: {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(Color(red: 87/255, green: 199/255, blue: 170/255))
                        }
                    .fixedSize()
                    .position(x:360)
                    }
                    
                    
                    Image("BrilliantLabsLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 12)
                        .position(x: 200, y: -10)
                    Text("arGPT")
                        .font(.system(size: 32, weight: .bold))
                        .position(x: 203,y:-77)
                    
                    Text("Let’s pair your device. Take your Monocle out of the case, and bring it close.")
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
                        .overlay(
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
                                    Text(searchingButton)
                                        .font(.system(size: 22, weight: .medium))
                                }
                                .padding(EdgeInsets(top: 20, leading: 40, bottom: 20, trailing: 40))
                                .padding(.horizontal, 60)
                                .background(Color(red: 242/255, green: 242/255, blue: 247/255))
                                .foregroundColor(Color(red: 142/255, green: 142/255, blue: 147/255))
                                .cornerRadius(15)
                            }
                        )
                }
            }
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
