import AppKit
import SwiftUI
import WebKit

/// In-bundle help article viewer. Navigation is restricted to the help articles directory.
struct HelpWebView: NSViewRepresentable {
    let articlesRoot: URL
    @Binding var articleURL: URL?
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    var navigateAction: HelpNavigateAction?
    var onTitleChange: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = view
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if let action = navigateAction {
            switch action {
            case .back where webView.canGoBack:
                webView.goBack()
            case .forward where webView.canGoForward:
                webView.goForward()
            default:
                break
            }
            DispatchQueue.main.async {
                context.coordinator.clearNavigateAction()
            }
        }
        guard let articleURL else { return }
        let key = articleURL.absoluteString
        if context.coordinator.lastLoaded == key { return }
        context.coordinator.lastLoaded = key
        webView.loadFileURL(articleURL, allowingReadAccessTo: articlesRoot)
    }

    enum HelpNavigateAction: Equatable {
        case back
        case forward
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: HelpWebView
        weak var webView: WKWebView?
        var lastLoaded: String?

        init(_ parent: HelpWebView) {
            self.parent = parent
        }

        func clearNavigateAction() {
            // Parent binding cleared by WelcomeHelpView after consume.
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onTitleChange?(webView.title ?? "")
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if url.scheme == "about" {
                decisionHandler(.allow)
                return
            }
            if url.isFileURL {
                let root = parent.articlesRoot.standardizedFileURL.path
                let path = url.standardizedFileURL.path
                if path.hasPrefix(root) {
                    decisionHandler(.allow)
                    return
                }
                decisionHandler(.cancel)
                return
            }
            if url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }
}
