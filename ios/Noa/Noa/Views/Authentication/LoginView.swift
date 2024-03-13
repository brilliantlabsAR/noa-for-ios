//
//  LoginView.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 3/13/24.
//

//
// TODO:
// -----
// - Need a button in DiscordLoginView to cancel out.
// - When Apple sign in initially returns, but before Noa sign in is complete, should display some sort of "signing in..." spinner
// - Need to implement account deletion and for Apple ID case, refresh token and identity token must be revoked
//

import SwiftUI

enum SignInSheetState {
    case hidden
    case discord
}

struct LoginView: View {
    @ObservedObject private var _settings: Settings
    @State private var signInSheet = SignInSheetState.hidden

    var body: some View {
        VStack {
            LogoView()

            switch signInSheet {
            case .hidden:
                Spacer()

                AppleSignInButtonView(onComplete: { (token: String?, userID: String?, fullName: String?, email: String?) in
                    signInSheet = .hidden
                    if let token = token {
                        // We obtained an API token and can start the app
                        _settings.setAPIToken(token)
                    }
                })
                .aspectRatio(contentMode: .fit)
                .frame(width: 300)
                .padding()

                GoogleSignInButtonView(onComplete: { (token: String?, userID: String?, fullName: String?, email: String?) in
                    signInSheet = .hidden
                    if let token = token {
                        _settings.setAPIToken(token)
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
                        // We obtained an API token and can start the app
                        _settings.setAPIToken(token)
                    }
                })
            }
        }
    }

    init(settings: Settings) {
        _settings = settings
    }
}

#Preview {
    LoginView(settings: Settings())
}
