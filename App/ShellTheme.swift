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
          the row that directly holds the back button. Removed outright: the
          native bar floats over the content instead of reserving a strip. */
    html.zcs div:has(> button[aria-label="返回任务首页"]) {
      display: none !important;
    }

    /* 2. The project / workspace chip row underneath it. */
    html.zcs [data-testid="workspace-header"] {
      display: none !important;
    }

    /* 3. Give the transcript room to scroll clear of the floating bar, so the
          first message is never permanently hidden behind it. */
    html.zcs [data-testid="v4-timeline"] {
      padding-top: 56px !important;
    }

    /* 4. Composer card: glassier surface instead of a flat block. */
    html.zcs [data-testid="v4-composer"] .rounded-2xl {
      border-radius: 26px !important;
      background: rgba(255,255,255,.055) !important;
      border-color: rgba(255,255,255,.10) !important;
      box-shadow: inset 0 1px 0 rgba(255,255,255,.12), 0 10px 26px rgba(0,0,0,.34) !important;
    }

    /* 5. The progress panel overhangs the top of the transcript and ignores the
          timeline's padding, so offset it directly. */
    html.zcs [data-testid="chat-summary-panel"] {
      margin-top: 52px !important;
    }

    /* 6. User messages become a filled accent bubble; assistant messages are
          already plain text and stay that way. */
    html.zcs .group\\/user-row > div.rounded-xl {
      background: linear-gradient(180deg, #3b86f8, #2a6ee6) !important;
      border-color: transparent !important;
      border-radius: 19px 19px 6px 19px !important;
      box-shadow: 0 4px 14px rgba(47,123,246,.22) !important;
    }
    html.zcs .group\\/user-row > div.rounded-xl,
    html.zcs .group\\/user-row > div.rounded-xl * {
      color: #fff !important;
    }

    /* 7. The model picker now lives in the attachment panel. Keep the trigger in
          the DOM with a zero-width box: the popover anchors to its rect, so it
          must not be display:none, but it should leave no gap in the row. */
    html.zcs [data-testid="chat-model-select-trigger"] {
      width: 0 !important;
      min-width: 0 !important;
      max-width: 0 !important;
      margin: 0 !important;
      padding: 0 !important;
      border: 0 !important;
      overflow: hidden !important;
      opacity: 0 !important;
      pointer-events: none !important;
    }
    """

    /// Installs the stylesheet as soon as the document has a head. The rules are
    /// all scoped to `html.zcs` and to elements that may appear later, so there
    /// is no need to wait for a particular screen — which matters because the
    /// app starts on the task list and only later opens a conversation.
    static var injectionScript: WKUserScript {
        let js = """
        (function () {
          function apply() {
            try {
              if (!document.head) { setTimeout(apply, 50); return; }
              document.documentElement.classList.add('zcs');
              if (document.getElementById('zcs-style')) return;
              var style = document.createElement('style');
              style.id = 'zcs-style';
              style.textContent = \(jsLiteral(css));
              document.head.appendChild(style);
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
