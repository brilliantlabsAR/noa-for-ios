//
//  AppleSignInButtonView.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 2/12/24.
//
//  Helpful documentation:
//      - https://developer.apple.com/documentation/sign_in_with_apple/sign_in_with_apple_rest_api/authenticating_users_with_sign_in_with_apple
//      - https://developer.apple.com/documentation/authenticationservices/implementing_user_authentication_with_sign_in_with_apple
//      - https://medium.com/playkids-tech-blog/implementing-sign-in-with-apple-on-the-server-side-76b711ed1f2b
//      - https://medium.com/swlh/get-the-most-out-of-sign-in-with-apple-e7e2ae072882
//      - https://dev.to/bionik6/sign-in-with-apple-from-client-to-server-side-validation-2df
//
// CHeck this: https://developer.apple.com/documentation/authenticationservices/asauthorizationappleidprovider/3175423-getcredentialstate
//

import AuthenticationServices
import SwiftUI

struct AppleSignInButtonView: View {
    @Environment(\.colorScheme) var colorScheme

    @State private var _nonce: String?
    @State private var _state: String?

    private let _onComplete: (String?, String?, String?, String?) -> Void

    init(onComplete: @escaping (String?, String?, String?, String?) -> Void) {
        _onComplete = onComplete
    }

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            // Generate random nonce and state values to check when we receive credential back
            _nonce = UUID().uuidString
            _state = UUID().uuidString

            // Sign in request, ask for user name and email
            request.requestedScopes = [.email, .fullName ]
            request.nonce = _nonce
            request.state = _state
        } onCompletion: { result in
            switch result {
            case .success(let results):
                print("[AppleSignInButtonView] Authorization successful")
                
                switch results.credential {
                case let appleIDCredential as ASAuthorizationAppleIDCredential:
                    guard appleIDCredential.state == _state else {
                        // We are supposed to get back the same state we sent with our request
                        print("[AppleSignInButtonView] Error: Credential state does not match!")
                        _onComplete(nil, nil, nil, nil)
                        return
                    }

                    guard let identityToken = appleIDCredential.identityToken else {
                        print("[AppleSignInButtonView] Error: No identity token provided despite authorization success")
                        _onComplete(nil, nil, nil, nil)
                        return
                    }

                    let token = String(decoding: identityToken, as: UTF8.self)
                    let userID = appleIDCredential.user
                    let fullName = getFullName(from: appleIDCredential)
                    let email = appleIDCredential.email

                    // Sign in with Noa server
                    signIn(with: .apple, token: token, userID: userID, fullName: fullName, email: email) { (authorizationToken: String?, email: String?) in
                        guard let authorizationToken = authorizationToken else {
                            print("[AppleSignInButtonView] Error: Noa server sign-in failed")
                            _onComplete(nil, nil, nil, nil)
                            return
                        }

                        // Succesfully signed in!
                        _onComplete(authorizationToken, userID, fullName, email)
                    }

                case let passwordCredential as ASPasswordCredential:
                    print("[AppleSignInButtonView] user=\(passwordCredential.user) password=\(passwordCredential.password)")
                    _onComplete(nil, nil, nil, nil)

                default:
                    _onComplete(nil, nil, nil, nil)
                }

            case .failure(let error):
                print("[AppleSignInButtonView] Authorization failed: \(error.localizedDescription)")
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .light ? .black : .white)
    }
}

fileprivate func getFullName(from credential: ASAuthorizationAppleIDCredential) -> String? {
    var nameComponents: [String] = []

    if let fullName = credential.fullName {
        if let firstName = fullName.givenName {
            nameComponents.append(firstName)
        }
        if let lastName = fullName.familyName {
            nameComponents.append(lastName)
        }
    }

    let fullName = nameComponents.joined(separator: " ")
    return fullName.count > 0 ? fullName : nil
}
