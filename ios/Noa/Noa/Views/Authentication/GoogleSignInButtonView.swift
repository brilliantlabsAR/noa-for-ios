//
//  GoogleSignInButtonView.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 2/13/24.
//

import GoogleSignIn
import GoogleSignInSwift
import SwiftUI

struct GoogleSignInButtonView: View {
    @Environment(\.colorScheme) var colorScheme

    private let _onComplete: (String?, String?, String?, String?) -> Void

    init(onComplete: @escaping (String?, String?, String?, String?) -> Void) {
        _onComplete = onComplete
    }

    var body: some View {
        GoogleSignInButton {
            handleSignIn()
        }
    }

    private func handleSignIn() {
        // The bridge method described at the bottom of this question did not work but would have been preferrable:
        // https://stackoverflow.com/questions/74908372/how-to-pass-rootviewcontroller-to-google-sign-in-in-swiftui
        guard let presentingViewController = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.rootViewController else { return }

        GIDSignIn.sharedInstance.signIn(withPresenting: /*_bridge.viewController*/ presentingViewController) { (result: GIDSignInResult?, error: Error?) in
            guard let result = result else {
                print("[GoogleSignInButtonView] Sign-in failed: \(error?.localizedDescription ?? "unknown error")")
                _onComplete(nil, nil, nil, nil)
                return
            }

            guard let token = result.user.idToken?.tokenString else {
                print("[GoogleSignInButtonView] Sign-in failed because ID token could not be retrieved")
                _onComplete(nil, nil, nil, nil)
                return
            }

            // Attempt to extract profile information and required token
            let userID = result.user.userID
            let fullName = getFullName(from: result.user.profile)
            let email = result.user.profile?.email

            //print("Token=\(token) userID=\(userID) fullName=\(fullName) email=\(email)")

            // Sign in with Noa server
            signIn(with: .google, token: token, userID: userID, fullName: fullName, email: email) { (authorizationToken: String?, email: String?) in
                guard let authorizationToken = authorizationToken else {
                    print("[GoogleSignInButtonView] Error: Noa server sign-in failed")
                    _onComplete(nil, nil, nil, nil)
                    return
                }

                // Successfully signed in
                _onComplete(authorizationToken, userID, fullName, email)
            }
        }
    }
}

fileprivate func getFullName(from profile: GIDProfileData?) -> String? {
    guard let profile = profile else {
        return nil
    }

    var nameComponents: [String] = []

    if let firstName = profile.givenName {
        nameComponents.append(firstName)
    }

    if let lastName = profile.familyName {
        nameComponents.append(lastName)
    }

    let fullName = nameComponents.joined(separator: " ")
    return fullName.count > 0 ? fullName : nil
}
