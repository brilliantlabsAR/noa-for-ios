//
//  ChatView.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 5/2/23.
//
//  Based on: https://iosapptemplates.com/blog/swiftui/swiftui-chat
//

import SwiftUI

/*
extension View {
    func inExpandingRectangle() -> some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
            self
        }
    }
}
*/

struct ChatView: View {
    // Data model
    @EnvironmentObject private var _chatMessageStore: ChatMessageStore
    @EnvironmentObject private var _settings: Settings

    // Monocle state
    @Binding private var _isMonocleConnected: Bool
    @Binding private var _pairedMonocleID: UUID?

    @State private var _textInput: String = ""
    
    @State private var popUpApiBox: Bool = false


    @State private var scale: CGFloat = 0 // For animation
    
    private let _onTextSubmitted: ((String) -> Void)?
    private let _onClearChatButtonPressed: (() -> Void)?

    var body: some View {
        ZStack {
            VStack(alignment: .center) {
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
                                popUpApiBox = true
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
                    .padding(.trailing)
                }
                .padding(.top)
                .frame(maxWidth: .infinity, alignment: .top)
                Spacer()
                
                // Message view
                // List of messages
                ScrollViewReader { scrollView in
                    List {
                        // Use enumerated array so that we can ID each element, allowing us to scroll to the bottom. Adding an
                        // EmptyView() at the end of the list with an ID does not seem to work.
                        ForEach(Array(_chatMessageStore.messages.enumerated()), id: \.element) { i, element in
                            MessageView(currentMessage: element).id(i)
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(.init(top: 5, leading: 10, bottom: 5, trailing: 10))
                        .listRowBackground(Color(UIColor.clear))
                        
                        // Empty element with anchor always at end of list that we can scroll to
                        Spacer().id(-1)
                            .listRowSeparator(.hidden)
                            .listRowInsets(.init(top: 5, leading: 10, bottom: 5, trailing: 10))
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(GroupedListStyle())  // take up full width
                    .scrollContentBackground(.hidden)
                    .onChange(of: _chatMessageStore.messages) { _ in
                        withAnimation {
                            // Scroll to bottom
                            scrollView.scrollTo(-1)
                        }
                    }
                }
                VStack {
                    if !_isMonocleConnected  {
                        if _pairedMonocleID != nil {
                            // We have a paired Monocle, it's just not connected
                            Text("No Monocle Connected! \(Image(systemName: "exclamationmark.circle"))")
                                .foregroundColor(Color.red)
                        } else {
                            Text("No Monocle Paired! \(Image(systemName: "exclamationmark.triangle"))")
                                .foregroundColor(Color.yellow)
                        }
                    } else if _chatMessageStore.messages.isEmpty {
                        // No messages
                        Text("Speak through your Monocle.")
                    } else {
                        Text("")
                    }
                }
                HStack(spacing: -35) {
                    
                    // Text entry
                    TextField("Ask a question", text: $_textInput)
                        .padding(6)
                        .padding(.leading, 10)
                        .background(RoundedRectangle(cornerRadius: 25).strokeBorder(Color.gray.opacity(0.5)))
                        .frame(minHeight: CGFloat(30))
                    
                    // Send button
                    Button(
                        action: {
                            _onTextSubmitted?(_textInput)
                            _textInput = ""
                        },
                        label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(.title))
                                .foregroundColor(Color(red: 87/255, green: 199/255, blue: 170/255))
                                .frame(minHeight: 30, alignment: .center)
                        }
                    )
                }
                .padding(.bottom, 5)
                .padding(.top, -10)
                .padding(.horizontal, 20)
            }
            .blur(radius: popUpApiBox ? 1 : 0)
            
            if popUpApiBox {
                Rectangle()
                    .fill(Color.black.opacity(0.4))
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.scale = 0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                self.scale = 0
                                self.popUpApiBox = false
                            }
                        }
                    }
                APIKeyPopupBox(scale: $scale, popUpApiBox: $popUpApiBox)
            }
        }
        .onAppear {
            // When view appears, check whether we need an API key
            popUpApiBox = _settings.apiKey.isEmpty
        }
    }

    public init(isMonocleConnected: Binding<Bool>, pairedMonocleID: Binding<UUID?>, onTextSubmitted: ((String) -> Void)? = nil, onClearChatButtonPressed: (() -> Void)? = nil) {
        __isMonocleConnected = isMonocleConnected
        __pairedMonocleID = pairedMonocleID
        _onTextSubmitted = onTextSubmitted
        _onClearChatButtonPressed = onClearChatButtonPressed
    }
}

struct APIKeyPopupBox: View {
    
    @Binding var scale: CGFloat
    @Binding var popUpApiBox: Bool
    @State private var apiCode: String = ""

    var body: some View {
        VStack {
            Text("Enter your OpenAI API key")
                .font(.system(size: 20, weight: .semibold))
                .padding(.top, 20)
                .padding(.bottom, 2)
            
            Text("If you don’t have a key, press \"Find My Key...\" to be taken to OpenAI.")
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
                    UIApplication.shared.open(URL(string: "http://platform.openai.com")!)
                }) {
                    Text("Find My Key...")
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

struct ChatView_Previews: PreviewProvider {
    private static var _chatMessageStore: ChatMessageStore = {
        let store = ChatMessageStore()
        store.putMessage(Message(content: "Hello", participant: Participant.user))
        store.putMessage(Message(content: "Message 2", participant: Participant.chatGPT))
        store.putMessage(Message(content: "Message 3", isError: true, participant: Participant.user))
        for i in 0..<100 {
            store.putMessage(Message(content: "A reply from ChatGPT... I am going to write a whole lot of text here. The objective is to wrap the line and ensure that multiple lines display properly! Let's see what happens.\nSingle newline.\n\nTwo newlines.", typingInProgress: false, participant: Participant.chatGPT))
        }
        return store
    }()

    static var previews: some View {
        ChatView(isMonocleConnected: .constant(false), pairedMonocleID: .constant(UUID()))
            .environmentObject(ChatView_Previews._chatMessageStore)
            .environmentObject(Settings())
    }
}
