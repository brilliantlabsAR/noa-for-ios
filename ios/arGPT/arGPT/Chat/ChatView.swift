//
//  ChatView.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 5/2/23.
//
//  Based on: https://iosapptemplates.com/blog/swiftui/swiftui-chat
//

import SwiftUI

extension View {
    func inExpandingRectangle() -> some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
            self
        }
    }
}

struct ChatView: View {
    @EnvironmentObject private var _chatMessageStore: ChatMessageStore
    @Binding private var _displaySettings: Bool
    @Binding private var _isMonocleConnected: Bool
    @Binding private var _pairedMonocleID: UUID?

    @State private var _textInput: String = ""
    @State private var _textEnteredViaKeyboard = false  // used to detect if keyboard text was submitted to show immediately, even if Monocle not connected

    private let _onTextSubmitted: ((String) -> Void)?
    private let _onClearChatButtonPressed: (() -> Void)?

    var body: some View {
        NavigationView {
            VStack {
                // Message view
                if !_isMonocleConnected && !_textEnteredViaKeyboard {
                    Spacer()
                    if _pairedMonocleID != nil {
                        // We have a paired Monocle, it's just not connected
                        Text("Monocle not connected.")
                        Text("Power it on nearby or tap \(Image(systemName: "gear"))")
                        Text("to connect a different one.")
                    } else {
                        Text("No Monocle paired.")
                        Text("Power on Monocle nearby")
                        Text("or tap \(Image(systemName: "gear")) to find one.")
                    }
                    Spacer()
                } else if _chatMessageStore.messages.isEmpty {
                    // No messages
                    Spacer()
                    Text("Speak through your Monocle.")
                    Spacer()
                } else {
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
                        //.scrollContentBackground(.hidden)
                        .onChange(of: _chatMessageStore.messages) { _ in
                            withAnimation {
                                // Scroll to bottom
                                scrollView.scrollTo(-1)
                            }
                        }
                    }
                }

                HStack {
                    // Settings button
                    Button(
                        action: {
                            _displaySettings = true
                        },
                        label: {
                            Image(systemName: "gear.circle.fill")
                                .font(.system(.title))
                                .frame(minHeight: 30, alignment: .center)
                        }
                    )

                    // Clear session button
                    Button(
                        role: .destructive,
                        action: {
                            _onClearChatButtonPressed?()
                            _textEnteredViaKeyboard = false
                        },
                        label: {
                            Image(systemName: "clear.fill")
                                .font(.system(.title))
                        }
                    )
                    .disabled(_chatMessageStore.messages.count == 0)

                    // Text entry
                    TextField("Question...", text: $_textInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(minHeight: CGFloat(30))

                    // Send button
                    Button(
                        action: {
                            _onTextSubmitted?(_textInput)
                            _textInput = ""
                            _textEnteredViaKeyboard = true
                        },
                        label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(.title))
                                .frame(minHeight: 30, alignment: .center)
                                .disabled(_textInput.isEmpty)
                        }
                    )
                }.frame(minHeight: CGFloat(50)).padding()
            }
            .navigationBarTitle(Text("arGPT Session"), displayMode: .inline)
        }
        .onChange(of: _isMonocleConnected) { _ in
            // Whenever Monocle is connected, clear the text entered flag so that next time it
            // disconnects, instructions are printed again
            if _isMonocleConnected {
                _textEnteredViaKeyboard = false
            }
        }
    }

    public init(displaySettings: Binding<Bool>, isMonocleConnected: Binding<Bool>, pairedMonocleID: Binding<UUID?>, onTextSubmitted: ((String) -> Void)? = nil, onClearChatButtonPressed: (() -> Void)? = nil) {
        __displaySettings = displaySettings
        __isMonocleConnected = isMonocleConnected
        __pairedMonocleID = pairedMonocleID
        _onTextSubmitted = onTextSubmitted
        _onClearChatButtonPressed = onClearChatButtonPressed
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
        ChatView(displaySettings: .constant(false), isMonocleConnected: .constant(true), pairedMonocleID: .constant(UUID()))
            .environmentObject(ChatView_Previews._chatMessageStore)
    }
}
