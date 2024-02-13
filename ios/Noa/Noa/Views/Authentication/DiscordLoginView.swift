//
//  DiscordLoginView.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 2/6/24.
//

import SwiftUI
import WebKit

struct DiscordLoginView: UIViewRepresentable {
    private let _url = URL(string: "https://api.brilliant.xyz/noa/login/discord")!
    private let _onDismiss: (String?, String?) -> Void

    init(onDismiss: @escaping (String?, String?) -> Void) {
        _onDismiss = onDismiss
    }

    func makeCoordinator() -> DiscordLoginViewCoordinator {
        return DiscordLoginViewCoordinator(onDismiss: _onDismiss)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        var request = URLRequest(url: _url)
        request.httpShouldHandleCookies = false
        webView.load(request)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
    }
}

class DiscordLoginViewCoordinator: NSObject, WKNavigationDelegate {
    private let _onDismiss: (String?, String?) -> Void

    init(onDismiss: @escaping (String?, String?) -> Void) {
        _onDismiss = onDismiss
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            // Just blanket allow in this case
            decisionHandler(WKNavigationActionPolicy.allow)
            return
        }
        
        print("[DiscordLoginView] Navigation action: \(url)")

        if url.lastPathComponent == "callback" {
            // Received the callback URL that contains our auth token
            let code = URLComponents(string: url.absoluteString)?.queryItems?.first(where: { $0.name == "code" })?.value
            if let code = code {
                // We have a code from Discord that we need to pass to Brilliant backend to
                // complete sign-in and get auth token
                print("[DiscordLoginView] Received code: \(code)")
                signIn(with: SocialIdentityProvider.discord, token: code, userID: nil, fullName: nil, email: nil) { [weak self] (authorizationToken: String?, email: String?) in
                    guard let authorizationToken = authorizationToken else {
                        print("[DiscordLoginView] Error: Discord login failed. Noa server sign-in failed.")
                        self?._onDismiss(nil, nil)
                        return
                    }

                    // Succesfully signed in!
                    self?._onDismiss(authorizationToken, email)
                }
            } else {
                print("[DiscordLoginView] Error: Discord login failed. Discord authorization server unexpectedly failed to provide a code.")
                _onDismiss(nil, nil)
            }
            decisionHandler(WKNavigationActionPolicy.cancel)
        } else {
            decisionHandler(WKNavigationActionPolicy.allow)
        }
    }
}
