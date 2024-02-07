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
    private let _onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
        _onDismiss = onDismiss
    }

    func makeCoordinator() -> DiscordLoginViewCoordinator {
        return DiscordLoginViewCoordinator(onDismiss: _onDismiss)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        let request = URLRequest(url: _url)
        webView.load(request)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
    }
}

class DiscordLoginViewCoordinator: NSObject, WKNavigationDelegate {
    private let _onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
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
            if let token = URLComponents(string: url.absoluteString)?.queryItems?.first(where: { $0.name == "code" })?.value {
                print("Extracted token: \(token)")
            } else {
                //TODO: handle this gracefully by emitting an error to the chat?
                fatalError("Discord login failed. Server unexpectedly failed to provide a token.")
            }
            decisionHandler(WKNavigationActionPolicy.cancel)
            _onDismiss()
        } else {
            decisionHandler(WKNavigationActionPolicy.allow)
        }
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
//        if let url = webView.url {
//            print("Navigated to: \(url)")
//        } else {
//            print("Unknown navigation")
//        }
    }

}
//
//#Preview {
//    DiscordLoginView()
//}
