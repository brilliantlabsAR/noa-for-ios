//
//  ChatView.swift
//  Noa
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

    // Bluetooth state
    @Binding private var _bluetoothEnabled: Bool

    // Allows pairing view to be brought up (replacing this one)
    @Binding private var _showPairingView: Bool

    // Which AI mode we are in
    @Binding private var _mode: AIAssistant.Mode

    // Stores text being input in text field
    @State private var _textInput: String = ""

    // Image detail view
    @State private var _expandedPicture: UIImage?
    @State private var _topLayerOpacity: CGFloat = 0    // animation

    // Chat callbacks
    private let _onTextSubmitted: ((String) -> Void)?
    private let _onClearChatButtonPressed: (() -> Void)?
    
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            VStack(alignment: .center) {
                // Title/navigation bar
                if _expandedPicture == nil {
                    ChatTitleBarView(
                        showPairingView: $_showPairingView,
                        bluetoothEnabled: $_bluetoothEnabled,
                        mode: $_mode
                    )
                } else {
                    PictureTitleBarView(expandedPicture: $_expandedPicture)
                }
                Spacer()
                
                // Message view (list of messages)
                ScrollViewReader { scrollView in
                    List {
                        // Use enumerated array so that we can ID each element, allowing us to scroll to the bottom. Adding an
                        // EmptyView() at the end of the list with an ID does not seem to work.
                        ForEach(Array(_chatMessageStore.messages.enumerated()), id: \.element) { i, element in
                            if _chatMessageStore.minutesElapsed(from: i - 1, to: i) >= 10 {
                                TimestampView(timestamp: element.timestamp)
                            }
                            MessageView(currentMessage: element, expandedPicture: $_expandedPicture).id(i)
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
                .allowsHitTesting(_expandedPicture == nil)  // do not allow input underneath picture
                .opacity(1 - _topLayerOpacity)              // hide when picture is being shown

                // Bottom bar: connection status and text entry
                if _expandedPicture == nil {
                    ChatTextFieldView(
                        isMonocleConnected: $_isMonocleConnected,
                        textInput: $_textInput,
                        onTextSubmitted: _onTextSubmitted
                    )
                } else {
                    PictureToolbarView(picture: _expandedPicture)
                }
            }
            .background(colorScheme == .dark ? Color(red: 28/255, green: 28/255, blue: 30/255) : Color(red: 242/255, green: 242/255, blue: 247/255))

            // Top layer of ZStack: Expanded picture
            if let picture = _expandedPicture {
                Image(uiImage: picture)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .onChange(of: _expandedPicture) {
            let opacity: CGFloat = $0 == nil ? 0 : 1
            withAnimation(.easeInOut(duration: 0.2)) {
                _topLayerOpacity = opacity
            }
        }
    }

    public init(
        isMonocleConnected: Binding<Bool>,
        bluetoothEnabled: Binding<Bool>,
        showPairingView: Binding<Bool>,
        mode: Binding<AIAssistant.Mode>,
        onTextSubmitted: ((String) -> Void)? = nil,
        onClearChatButtonPressed: (() -> Void)? = nil
    ) {
        __isMonocleConnected = isMonocleConnected
        __bluetoothEnabled = bluetoothEnabled
        __showPairingView = showPairingView
        __mode = mode
        _onTextSubmitted = onTextSubmitted
        _onClearChatButtonPressed = onClearChatButtonPressed
    }
}

fileprivate struct ChatTitleBarView: View {
    @EnvironmentObject private var _settings: Settings

    @Binding var showPairingView: Bool
    @Binding var bluetoothEnabled: Bool
    @Binding var mode: AIAssistant.Mode

    var body: some View {
        HStack {
            Spacer()
                .frame(width: 70)

            // Title
            Text("Noa")
                .font(.system(size: 22, weight: .bold))
                .frame(maxWidth: .infinity)

            // Settings menu
            SettingsMenuView(
                showPairingView: $showPairingView,
                bluetoothEnabled: $bluetoothEnabled,
                mode: $mode
            )
            .environmentObject(_settings)
            .padding(.trailing)
        }
        .padding(.top)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

fileprivate struct ChatTextFieldView: View {
    @Binding var isMonocleConnected: Bool
    @Binding var textInput: String
    let onTextSubmitted: ((String) -> Void)?

    var body: some View {
        VStack {
            // Connection status
            VStack {
                if !isMonocleConnected  {
                    Text("Not Connected \(Image(systemName: "exclamationmark.circle"))")
                        .foregroundColor(Color.red)
                        .padding(.bottom)
                } else {
                    Text("")
                }
            }

            // Text input box
            HStack(spacing: -35) {
                // Text entry
                TextField("Ask a question", text: $textInput)
                    .padding(6)
                    .padding(.leading, 10)
                    .background(RoundedRectangle(cornerRadius: 25).strokeBorder(Color.gray.opacity(0.5)))
                    .frame(minHeight: CGFloat(30))

                // Send button
                let textFieldEmpty = textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let sendButtonColor = textFieldEmpty ? Color(UIColor.systemGray) : Color(red: 87/255, green: 199/255, blue: 170/255)
                Button(
                    action: {
                        onTextSubmitted?(textInput)
                        textInput = ""
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
    }
}

fileprivate struct PictureTitleBarView: View {
    @Binding var expandedPicture: UIImage?

    var body: some View {
        HStack {
            Spacer()
            Button("Done") {
                // Close
                expandedPicture = nil
            }
            .padding(.trailing)
            .font(.system(size: 22, weight: .bold))
        }
        .padding(.top)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

fileprivate struct PictureToolbarView: View {
    private let _image: Image?

    var body: some View {
        HStack {
            if let image = _image {
                ShareLink(item: image, preview: SharePreview("Picture", image: image)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .padding(.leading)
            }
            Spacer()
        }
    }

    init(picture: UIImage?) {
        if let picture = picture {
            _image = Image(uiImage: picture)
        } else {
            _image = nil
        }
    }
}

struct ChatView_Previews: PreviewProvider {
    private static var _chatMessageStore: ChatMessageStore = {
        let store = ChatMessageStore()
        let imageURL = Bundle.main.url(forResource: "Tahoe", withExtension: "jpg")!
        let imageData = try! Data(contentsOf: imageURL)
        let image = UIImage(data: imageData)
        store.putMessage(Message(text: "Hello", participant: Participant.user))
        store.putMessage(Message(text: "Message 2", participant: Participant.assistant))
        store.putMessage(Message(text: "Message 3", isError: true, participant: Participant.user))
        store.putMessage(Message(text: "Lake Tahoe!", picture: image, participant: Participant.user))
        store.putMessage(Message(text: "Assistant response", picture: image, participant: Participant.assistant))
        store.putMessage(Message(text: "Translator version", picture: image, participant: Participant.translator))
        for i in 0..<100 {
            store.putMessage(Message(text: "A reply from ChatGPT... I am going to write a whole lot of text here. The objective is to wrap the line and ensure that multiple lines display properly! Let's see what happens.\nSingle newline.\n\nTwo newlines.", typingInProgress: false, participant: Participant.assistant))
        }
        return store
    }()

    static var previews: some View {
        ChatView(
            isMonocleConnected: .constant(false),
            bluetoothEnabled: .constant(false),
            showPairingView: .constant(false),
            mode: .constant(.assistant)
        )
            .environmentObject(ChatView_Previews._chatMessageStore)
            .environmentObject(Settings())
    }
}
