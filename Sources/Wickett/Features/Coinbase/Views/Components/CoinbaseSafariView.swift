import SwiftUI
import WebKit

/// Embedded WebView for Coinbase checkout flow - provides native in-app experience
struct CoinbaseSafariView: UIViewRepresentable {
    let url: URL
    let onDismiss: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        // Enable Apple Pay and other payment APIs
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.bounces = true

        // Load the Coinbase checkout URL
        let request = URLRequest(url: url)
        webView.load(request)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Check if we've navigated to a completion URL
            if let currentURL = webView.url?.absoluteString {
                // Coinbase redirects to these URLs on completion/cancellation
                if currentURL.contains("wickett://coinbase-onramp-complete") ||
                   currentURL.contains("wickett://coinbase-offramp-complete") ||
                   currentURL.contains("close") {
                    onDismiss()
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            #if DEBUG
            print("WebView navigation failed: \(error.localizedDescription)")
            #endif
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            #if DEBUG
            print("WebView provisional navigation failed: \(error.localizedDescription)")
            #endif
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Handle deep links back to the app
            if let url = navigationAction.request.url,
               url.scheme == "wickett" {
                decisionHandler(.cancel)
                onDismiss()
                return
            }

            decisionHandler(.allow)
        }
    }
}
