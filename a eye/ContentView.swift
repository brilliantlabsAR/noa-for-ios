//
//  ContentView.swift
//  a eye
//
//  Created by Raj Nakarja on 2023-03-28.
//

import SwiftUI
import Combine

struct LoadingView: View {
    var body: some View {
        ZStack {
            Color(red: 0.15, green: 0.15, blue: 0.15)
                .opacity(0.5)
            VStack {
                Image("BluetoothIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50)
                    .colorInvert()
                Spacer()
                    .frame(height: 30)
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(2)
            }
        }
    }
}

struct ContentView: View {
    
    @State private var bluetoothScanning = true
    @State var chatMessages: [ChatMessage] = []
    @State var messageText: String = ""
    let openAIService = OpenAIService()
    @State var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        ZStack {
            Color(red: 0.15, green: 0.15, blue: 0.15)
                 .ignoresSafeArea()

            VStack {
                ScrollView {
                    LazyVStack {
                        ForEach(chatMessages, id: \.id) { message in
                            messageView(message: message)
                        }
                    }
                }
                HStack {
                    TextField("Ask something", text: $messageText)
                        .colorScheme(.dark)
                        .padding()
                        .background(.gray.opacity(0.1))
                        .cornerRadius(12)
                    Button {
                        sendMessage()
                    } label: {
                        Text("Send")
                            .foregroundColor(.black)
                            .padding()
                            .background(.white.opacity(0.9))
                            .cornerRadius(12)
                    }
                }
            }
            .padding()

            if (bluetoothScanning){
                LoadingView()
            }
        }
        .onAppear() {
            startFakeBluetoothConnection()
        }
    }
    
    func sendMessage() {
        let myMessage = ChatMessage(id: UUID().uuidString, content: messageText, dateCreated: Date(), sender: .me)
        chatMessages.append(myMessage)
        openAIService.sendMessage(message: messageText).sink { completion in
            // Handle errors
        } receiveValue: { response in
            guard let textResponse = response.choices.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            let gptMessage = ChatMessage(id: response.id, content: textResponse, dateCreated: Date(), sender: .gpt)
            chatMessages.append(gptMessage)
        }
        .store(in: &cancellables)
        messageText = "";
    }
    
    func messageView(message: ChatMessage) -> some View {
        HStack {
            if message.sender == .me { Spacer() }
            Text(message.content)
                .padding()
                .foregroundColor(.white)
                .background(message.sender == .me ? .blue : .gray.opacity(0.1))
                .cornerRadius(16)
            if message.sender == .gpt { Spacer() }
        }
    }
    
    func startFakeBluetoothConnection() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            bluetoothScanning = false
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct ChatMessage {
    let id: String
    let content: String
    let dateCreated: Date
    let sender: MessageSender
}

enum MessageSender {
    case me
    case gpt
}

extension ChatMessage {
    static let sampleMessages = [
        ChatMessage(id: UUID().uuidString, content: "Sample message from me", dateCreated: Date(), sender: .me),
        ChatMessage(id: UUID().uuidString, content: "Sample message from gpt", dateCreated: Date(), sender: .gpt),
        ChatMessage(id: UUID().uuidString, content: "Sample message from me", dateCreated: Date(), sender: .me),
        ChatMessage(id: UUID().uuidString, content: "Sample message from gpt", dateCreated: Date(), sender: .gpt),
    ]
}
