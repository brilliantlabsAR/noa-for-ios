//
//  ChatView.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 5/2/23.
//
//  Based on: https://iosapptemplates.com/blog/swiftui/swiftui-chat
//

import SwiftUI

struct ChatView: View {
    // Data model
    @EnvironmentObject private var _chatMessageStore: ChatMessageStore
    @EnvironmentObject private var _settings: Settings

    // Monocle state
    @Binding private var _isMonocleConnected: Bool
    @Binding private var _pairedMonocleID: UUID?

    // Bluetooth state
    @Binding private var _bluetoothEnabled: Bool

    // Allows pairing view to be brought up (replacing this one)
    @Binding private var _showPairingView: Bool

    // Which AI mode we are in
    @Binding private var _mode: ChatGPT.Mode

    // Stores text being input in text field
    @State private var _textInput: String = ""

    // Popup API box state
    @State private var popUpApiBox: Bool = false
    @State private var popupApiBoxScale: CGFloat = 0   // animation

    // Chat callbacks
    private let _onTextSubmitted: ((String) -> Void)?
    private let _onClearChatButtonPressed: (() -> Void)?
    
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            VStack(alignment: .center) {
                // Top title bar
                HStack {
                    Spacer()
                        .frame(width: 70)

                    // Title
                    Text("Noa")
                        .font(.system(size: 22, weight: .bold))
                        .frame(maxWidth: .infinity)
                    
                    // Settings menu
                    SettingsMenuView(
                        popUpApiBox: $popUpApiBox,
                        showPairingView: $_showPairingView,
                        bluetoothEnabled: $_bluetoothEnabled,
                        mode: $_mode
                    )
                        .environmentObject(_settings)
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
                        Text("Not Connected \(Image(systemName: "exclamationmark.circle"))")
                            .foregroundColor(Color.red)
                            .padding(.bottom)
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
                    let textFieldEmpty = _textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let sendButtonColor = textFieldEmpty ? Color(UIColor.systemGray) : Color(red: 87/255, green: 199/255, blue: 170/255)
                    Button(
                        action: {
                            _onTextSubmitted?(_textInput)
                            _textInput = ""
                        },
                        label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(.title))
                                .foregroundColor(sendButtonColor)
                                .symbolRenderingMode(.multicolor)
                                .frame(minHeight: 29, alignment: .center)
                                .padding(1)
                        }
                    )
                    .disabled(textFieldEmpty)
                }
                .padding(.bottom, 5)
                .padding(.top, -10)
                .padding(.horizontal, 20)
            }
            .background(colorScheme == .dark ? Color(red: 28/255, green: 28/255, blue: 30/255) : Color(red: 242/255, green: 242/255, blue: 247/255))
            .blur(radius: popUpApiBox ? 1 : 0)
            
            if popUpApiBox {
                Rectangle()
                    .fill(Color.black.opacity(0.4))
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.popupApiBoxScale = 0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                self.popupApiBoxScale = 0
                                self.popUpApiBox = false
                            }
                        }
                    }
                APIKeyPopupBoxView(scale: $popupApiBoxScale, popUpApiBox: $popUpApiBox)
                    .environmentObject(_settings)
            }
        }
        .onAppear {
            // When view appears, check whether we need an API key
            popUpApiBox = _settings.apiKey.isEmpty
        }
    }

    public init(
        isMonocleConnected: Binding<Bool>,
        pairedMonocleID: Binding<UUID?>,
        bluetoothEnabled: Binding<Bool>,
        showPairingView: Binding<Bool>,
        mode: Binding<ChatGPT.Mode>,
        onTextSubmitted: ((String) -> Void)? = nil,
        onClearChatButtonPressed: (() -> Void)? = nil
    ) {
        __isMonocleConnected = isMonocleConnected
        __pairedMonocleID = pairedMonocleID
        __bluetoothEnabled = bluetoothEnabled
        __showPairingView = showPairingView
        __mode = mode
        _onTextSubmitted = onTextSubmitted
        _onClearChatButtonPressed = onClearChatButtonPressed
    }
}

struct ChatView_Previews: PreviewProvider {
    private static var _chatMessageStore: ChatMessageStore = {
        let store = ChatMessageStore()
        store.putMessage(Message(content: "Hello", participant: Participant.user))
        store.putMessage(Message(content: "Message 2", participant: Participant.assistant))
        store.putMessage(Message(content: "Message 3", isError: true, participant: Participant.user))
        for i in 0..<100 {
            store.putMessage(Message(content: "A reply from ChatGPT... I am going to write a whole lot of text here. The objective is to wrap the line and ensure that multiple lines display properly! Let's see what happens.\nSingle newline.\n\nTwo newlines.", typingInProgress: false, participant: Participant.assistant))
        }
        return store
    }()

    static var previews: some View {
        ChatView(
            isMonocleConnected: .constant(false),
            pairedMonocleID: .constant(UUID()),
            bluetoothEnabled: .constant(false),
            showPairingView: .constant(false),
            mode: .constant(.assistant)
        )
            .environmentObject(ChatView_Previews._chatMessageStore)
            .environmentObject(Settings())
    }
}
