//
//  ContentView.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 7/23/23.
//
//  Top-level application view.
//

//
// TODO:
// -----
// - Auth token needs to be stored in Keychain, not Settings!
// - Need a button in DiscordLoginView to cancel out.
// - When Apple sign in initially returns, but before Noa sign in is complete, should display some sort of "signing in..." spinner
// - Need to implement account deletion and for Apple ID case, refresh token and identity token must be revoked
//

import CoreBluetooth
import Foundation
import GoogleSignIn
import SwiftUI

enum SignInSheetState {
    case hidden
    case discord
}

struct ContentView: View {
    @ObservedObject private var _settings: Settings
    private let _chatMessageStore: ChatMessageStore
    @ObservedObject private var _frameController: FrameController

    @Environment(\.colorScheme) var colorScheme

    // Login
    @State private var signInSheet = SignInSheetState.hidden

    var body: some View {
        ZStack {
            colorScheme == .dark ? Color(red: 28/255, green: 28/255, blue: 30/255).edgesIgnoringSafeArea(.all) : Color(red: 242/255, green: 242/255, blue: 247/255).edgesIgnoringSafeArea(.all)

            VStack {
                if isLoggedIn() {
                    MainAppView(settings: _settings, chatMessageStore: _chatMessageStore, frameController: _frameController)
                } else {
                    LogoView()

                    switch signInSheet {
                    case .hidden:
                        Spacer()

                        AppleSignInButtonView(onComplete: { (token: String?, userID: String?, fullName: String?, email: String?) in
                            signInSheet = .hidden
                            if let token = token {
                                // We obtained an auth token and can start the app
                                _settings.setAuthorizationToken(token)
                            }
                        })
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 300)
                        .padding()

                        GoogleSignInButtonView(onComplete: { (token: String?, userID: String?, fullName: String?, email: String?) in
                            signInSheet = .hidden
                            if let token = token {
                                _settings.setAuthorizationToken(token)
                            }
                        })
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 300)
                        .padding()

                        Button(
                            action: {
                                signInSheet = .discord
                            },
                            label: {
                                Image("DiscordLogo")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 300)
                            }
                        )
                            .padding()
                        Text("Choose a method to sign in with.")
                            .font(.system(size: 15))
                            .frame(width: 314, height: 60)
                        Spacer()

                    case .discord:
                        DiscordLoginView(onDismiss: { (token: String?, email: String?) in
                            signInSheet = .hidden
                            if let token = token {
                                // We obtained an auth token and can start the app
                                _settings.setAuthorizationToken(token)
                            }
                        })
                    }
                }
            }
        }
        /*
        .onOpenURL(perform: { url in
            GIDSignIn.sharedInstance.handle(url)
        })
        .onAppear {
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                // Check if 'user' exists, otherwise, handle 'error'
                //TODO: I don't think we need this. We use sign in just for user validation and then store our own token.
            }
        }
         */
    }

    init(settings: Settings, chatMessageStore: ChatMessageStore, frameController: FrameController) {
        _settings = settings
        _chatMessageStore = chatMessageStore
        _frameController = frameController
    }

    private func isLoggedIn() -> Bool {
        return _settings.authorizationToken != nil
    }
}

struct ContentView_Previews: PreviewProvider {
    private static var _settings = Settings()
    private static var _chatMessageStore = ChatMessageStore()
    private static var _frameController = {
        return FrameController(settings: Self._settings, messages: Self._chatMessageStore)
    }()

    static var previews: some View {
        ContentView(
            settings: Self._settings,
            chatMessageStore: Self._chatMessageStore,
            frameController: Self._frameController
        )
    }
}

