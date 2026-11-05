import SwiftUI
import WebKit

final class WebModel: NSObject, ObservableObject {
    @Published var unreachable = false
    @Published var loading = true

    let webView: WKWebView

    private let url: URL
    private var savedScroll = "[]"
    private var reachabilityTask: Task<Void, Never>?

    init(url: URL) {
        self.url = url

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        // The default store keeps cookies and localStorage across relaunches,
        // so the remote session survives a cold start.
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // An app that declares no localizations reports en-US to the web view,
        // so the page falls back to English even on a Chinese device. Correct
        // navigator.language before any page script runs.
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.languageOverrideScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false

        // Capture the scroll offset while the page is still alive; once the web
        // content process is gone we can no longer run JavaScript in it.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(captureScroll),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        reload()
    }

    deinit {
        reachabilityTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Loading

    func reload(fromOrigin: Bool = false) {
        loading = true
        let policy: URLRequest.CachePolicy = fromOrigin
            ? .reloadIgnoringLocalAndRemoteCacheData
            : .useProtocolCachePolicy
        webView.load(URLRequest(url: url, cachePolicy: policy))
    }

    /// Escape hatch for when the desktop app shipped new assets and the cached
    /// bundle no longer matches the server.
    func clearCacheAndReload() {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
            self?.reload(fromOrigin: true)
        }
    }

    /// Called when the app returns to the foreground. A hung page cannot tell us
    /// anything, so ask the network directly and cover it with a native prompt.
    func checkReachability() {
        reachabilityTask?.cancel()
        reachabilityTask = Task { [weak self] in
            guard let self else { return }
            let result = await ConnectionProbe.run(self.url, timeout: 5)
            await MainActor.run {
                switch result {
                case .ok:
                    self.unreachable = false
                case .failed:
                    self.unreachable = !self.webView.isLoading
                }
            }
        }
    }

    // MARK: - Scroll preservation

    @objc private func captureScroll() {
        webView.evaluateJavaScript(Self.captureScrollScript) { [weak self] result, _ in
            if let json = result as? String {
                self?.savedScroll = json
            }
        }
    }

    private func restoreScroll() {
        guard savedScroll != "[]" else { return }
        webView.callAsyncJavaScript(
            """
            try {
              const saved = JSON.parse(raw);
              const nodes = document.querySelectorAll('*');
              for (const [index, top] of saved) {
                const el = nodes[index];
                if (el) el.scrollTop = top;
              }
            } catch (e) {}
            """,
            arguments: ["raw": savedScroll],
            in: nil,
            in: .page
        ) { _ in }
    }

    /// Chat UIs scroll an inner container rather than the window, so record the
    /// topmost scroll offset of every element and restore them by DOM order.
    private static let captureScrollScript = """
    (function () {
      const out = [];
      document.querySelectorAll('*').forEach(function (el, index) {
        if (el.scrollTop > 0) out.push([index, el.scrollTop]);
      });
      return JSON.stringify(out);
    })();
    """

    private static var languageOverrideScript: String {
        let preferred = Locale.preferredLanguages
        let primary = preferred.first ?? "en-US"
        let languages = preferred.isEmpty ? [primary] : Array(preferred.prefix(3))
        return """
        (function () {
          try {
            Object.defineProperty(navigator, 'language', { get: function () { return \(jsonString(primary)); } });
            Object.defineProperty(navigator, 'languages', { get: function () { return \(jsonArray(languages)); } });
          } catch (e) {}
        })();
        """
    }

    private static func jsonString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let text = String(data: data, encoding: .utf8) else { return "\"en-US\"" }
        // JSONSerialization returns ["zh-CN"]; drop the brackets.
        return String(text.dropFirst().dropLast())
    }

    private static func jsonArray(_ values: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: values),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }
}

// MARK: - WKNavigationDelegate

extension WebModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false
        unreachable = false
        restoreScroll()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loading = false
        checkReachability()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        loading = false
        checkReachability()
    }

    /// iOS reclaims the web content process under memory pressure — the event
    /// Safari answers with a "reload" prompt. Reload quietly instead.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        reload()
    }
}

// MARK: - SwiftUI bridge

struct ZCodeWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
