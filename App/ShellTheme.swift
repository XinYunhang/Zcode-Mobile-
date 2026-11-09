import Foundation
import WebKit

/// Styles injected into the remote web UI.
///
/// The page is a versioned SPA (`/remote/v4/<version>/`), and its controls carry
/// stable `data-testid` hooks that the app itself also selects on. Everything
/// below targets either those hooks or semantic class names, and every rule is
/// scoped to `html.zcs` so a failed injection leaves the page untouched.
enum ShellTheme {
    static let css = """
    /* 1. The conversation's own title bar. It has no testid, so identify it as
          the row that directly holds the back button. Keep its height (slightly
          taller, to match the native bar) so nothing reflows. */
    html.zcs div:has(> button[aria-label="返回任务首页"]) {
      height: 52px !important;
      opacity: 0 !important;
      pointer-events: none !important;
      border-bottom-color: transparent !important;
    }

    /* 2. The project / workspace chip row underneath it. */
    html.zcs [data-testid="workspace-header"] {
      display: none !important;
    }

    /* 3. Composer card: glassier surface instead of a flat block. */
    html.zcs [data-testid="v4-composer"] .rounded-2xl {
      border-radius: 26px !important;
      background: rgba(255,255,255,.055) !important;
      border-color: rgba(255,255,255,.10) !important;
      box-shadow: inset 0 1px 0 rgba(255,255,255,.12), 0 10px 26px rgba(0,0,0,.34) !important;
    }
    """

    /// Applies the stylesheet once the app has actually rendered, and marks the
    /// root so the rules only ever take effect against a page we recognise.
    /// The SPA mounts after document end, so this retries for a few seconds.
    static var injectionScript: WKUserScript {
        let js = """
        (function () {
          var tries = 0;
          function apply() {
            try {
              if (!document.querySelector('[data-testid="v4-composer"], [data-testid="workspace-header"]')) {
                if (++tries < 40) { setTimeout(apply, 250); }
                return;
              }
              document.documentElement.classList.add('zcs');
              if (!document.getElementById('zcs-style')) {
                var style = document.createElement('style');
                style.id = 'zcs-style';
                style.textContent = \(jsLiteral(css));
                document.head.appendChild(style);
              }
            } catch (e) {}
          }
          apply();
        })();
        """
        return WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    /// JSON-encodes a string for safe embedding in JavaScript source.
    private static func jsLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let text = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        // JSONSerialization returns ["..."], drop the surrounding brackets.
        return String(text.dropFirst().dropLast())
    }
}
