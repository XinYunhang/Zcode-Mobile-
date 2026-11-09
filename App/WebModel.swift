import UIKit
import SwiftUI
import WebKit

final class WebModel: NSObject, ObservableObject {
    @Published var unreachable = false
    @Published var loading = true
    /// True while a conversation is open, so the native bar only covers the
    /// strips it was designed for. Starts false: the app opens on the task list,
    /// and showing the bar before the first check made it flash on launch.
    @Published var isChat = false
    /// Mirrors of the page's current selections, shown in the native tool sheet.
    @Published var modelName = ""
    @Published var modeName = ""
    /// Files handed to the page's file input. The page renders its own preview
    /// inside the composer, which the native bar covers, so the strip is drawn
    /// here from what the picker actually returned.
    @Published var attachments: [PendingAttachment] = []

    struct PendingAttachment: Identifiable {
        let id = UUID()
        let url: URL
        let image: UIImage?
        var name: String { url.lastPathComponent }
    }

    let webView: WKWebView

    private let url: URL
    private var savedScroll = "[]"
    private var reachabilityTask: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var routeTimer: Timer?

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
        configuration.userContentController.addUserScript(ShellTheme.injectionScript)
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.composerToolsScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(beginKeepAlive),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(endKeepAlive),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        reload()

        // The page routes on its own (picking a task, going back), so poll the
        // one cheap signal that tells us which surface is on screen.
        let timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            self?.pollRoute()
        }
        RunLoop.main.add(timer, forMode: .common)
        routeTimer = timer
    }

    deinit {
        routeTimer?.invalidate()
        reachabilityTask?.cancel()
        NotificationCenter.default.removeObserver(self)
        endKeepAlive()
    }

    private func pollRoute() {
        let js = """
        (function(){
          var composer = document.querySelector('[data-testid="v4-composer"]');
          if (!composer) { return { chat: false, model: '', mode: '' }; }
          function text(selector) {
            var el = document.querySelector(selector);
            return el ? (el.innerText || '').replace(/\\s+/g, ' ').trim() : '';
          }
          return {
            chat: true,
            model: text('[data-testid="chat-model-select-trigger"]'),
            mode: text('[data-testid="chat-mode-select-trigger"]')
          };
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] value, _ in
            guard let self, let dict = value as? [String: Any] else { return }
            let chat = (dict["chat"] as? NSNumber)?.boolValue ?? (dict["chat"] as? Bool) ?? false
            let model = dict["model"] as? String ?? ""
            let mode = dict["mode"] as? String ?? ""
            DispatchQueue.main.async {
                if self.isChat != chat { self.isChat = chat }
                if self.modelName != model { self.modelName = model }
                if self.modeName != mode { self.modeName = mode }
            }
        }
    }

    // MARK: - Background keep-alive

    /// iOS suspends the app seconds after it leaves the foreground, and a
    /// suspended process cannot hold a socket open. A background task buys
    /// roughly thirty seconds of real execution, which is enough to survive a
    /// quick switch to another app.
    @objc private func beginKeepAlive() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "keepAlive") { [weak self] in
            self?.endKeepAlive()
        }
    }

    @objc private func endKeepAlive() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
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

    // MARK: - Driving the page

    /// Clicks a control the page marks with `data-testid`. Fire-and-forget: the
    /// page owns the result, we only need the tap to happen.
    func tap(testID: String) {
        let id = Self.jsString(testID)
        webView.evaluateJavaScript(
            "(function(){var el=document.querySelector('[data-testid='+\(id)+']');if(el){el.click();}})();"
        )
    }

    /// Leaves the conversation and returns to the task list. The page's back
    /// control has no testid; it is the only button in the title row, and its
    /// accessibility label is the one stable handle on it.
    func exitToTaskList() {
        webView.evaluateJavaScript("""
        (function(){
          var el = document.querySelector('button[aria-label="返回任务首页"]');
          if (el) { el.click(); return; }
          history.back();
        })();
        """)
    }

    private static func jsString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let text = String(data: data, encoding: .utf8) else { return "\"\"" }
        // JSONSerialization returns ["..."], drop the brackets.
        return String(text.dropFirst().dropLast())
    }

    // MARK: - Native composer bridge

    /// Presses a control the way a finger would. Radix triggers open on
    /// pointerdown, so a bare `click()` is ignored.
    private func pointerTap(selector: String) {
        let literal = Self.jsString(selector)
        webView.evaluateJavaScript("""
        (function(sel){
          var el = document.querySelector(sel);
          if (!el) { return; }
          var r = el.getBoundingClientRect();
          var x = r.left + r.width / 2;
          var y = r.top + r.height / 2;
          function init(b, d) {
            return { bubbles: true, cancelable: true, composed: true, view: window,
                     detail: d, clientX: x, clientY: y, screenX: x, screenY: y,
                     pointerId: 1, pointerType: 'touch', isPrimary: true,
                     button: 0, buttons: b };
          }
          var Ctor = window.PointerEvent || window.MouseEvent;
          el.dispatchEvent(new Ctor('pointerdown', init(1, 0)));
          el.dispatchEvent(new Ctor('pointerup', init(0, 0)));
          el.dispatchEvent(new Ctor('click', init(0, 1)));
        })(\(literal));
        """)
    }

    /// Opens the page's attachment panel — used for the plugin list, which stays
    /// a web surface in this build.
    func openAttachmentPanel() {
        pointerTap(selector: "[data-testid=chat-attachment-button]")
    }

    /// Opens the page's attachment panel and immediately presses its first item,
    /// which is what raises the system file picker.
    func pickAttachment() {
        pointerTap(selector: "[data-testid=chat-attachment-button]")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.pointerTap(selector: "[data-testid=chat-attachment-menu-item]")
        }
    }

    func openModelPopover() {
        pointerTap(selector: "[data-testid=chat-model-select-trigger]")
    }

    func openModePopover() {
        pointerTap(selector: "[data-testid=chat-mode-select-trigger]")
    }

    /// Writes the draft into the page's rich-text editor and presses send.
    /// `execCommand('insertText')` is what the editor actually listens for;
    /// assigning textContent or dispatching input events does not update it.
    /// An empty draft still presses send, so attachments alone can be sent.
    func send(_ draft: String) {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = Self.jsString(trimmed)

        webView.evaluateJavaScript("""
        (function(){
          var text = \(payload);
          var input = document.querySelector('[data-testid="v4-composer-input"]');
          if (input && text.length) {
            input.focus();
            var sel = window.getSelection();
            var range = document.createRange();
            range.selectNodeContents(input);
            sel.removeAllRanges();
            sel.addRange(range);
            document.execCommand('delete', false);
            document.execCommand('insertText', false, text);
          }

          window.setTimeout(function(){
            var btn = document.querySelector('[data-testid="v4-composer-send"]');
            if (!btn) { return; }
            var r = btn.getBoundingClientRect();
            var x = r.left + r.width / 2;
            var y = r.top + r.height / 2;
            function init(b, d) {
              return { bubbles: true, cancelable: true, composed: true, view: window,
                       detail: d, clientX: x, clientY: y, screenX: x, screenY: y,
                       pointerId: 1, pointerType: 'touch', isPrimary: true,
                       button: 0, buttons: b };
            }
            var Ctor = window.PointerEvent || window.MouseEvent;
            btn.dispatchEvent(new Ctor('pointerdown', init(1, 0)));
            btn.dispatchEvent(new Ctor('pointerup', init(0, 0)));
            btn.dispatchEvent(new Ctor('click', init(0, 1)));
          }, text.length ? 180 : 60);
        })();
        """)
    }

    /// Called when the app returns to the foreground. A hung page cannot tell us
    /// anything, so ask the network directly and cover it with a native prompt.
    func checkReachability() {
        reachabilityTask?.cancel()
        reachabilityTask = Task { [weak self] in
            guard let self else { return }

            // The network stack is often not ready the instant the app wakes up,
            // so a single failure right after resume means nothing.
            for attempt in 0..<2 {
                if attempt > 0 {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                }
                if Task.isCancelled { return }
                if case .ok = await ConnectionProbe.run(self.url, timeout: 4) {
                    await MainActor.run { self.unreachable = false }
                    return
                }
            }

            await MainActor.run {
                // A page that is still loading will report its own failure.
                if !self.webView.isLoading {
                    self.unreachable = true
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

    // MARK: - Composer tools

    /// Two page-level affordances the remote UI does not expose on its own:
    ///
    /// * A "模型 · <name>" row at the top of the attachment popover, which
    ///   closes the popover and then opens the real model picker.
    /// * A 500 ms long press on send that opens the model picker instead of
    ///   sending the message.
    ///
    /// The model picker opens from a real pointer sequence: its Radix trigger
    /// ignores `el.click()` entirely. The plus panel is rebuilt by React on
    /// every open, so a MutationObserver re-inserts our row each time instead
    /// of relying on the node surviving.
    private static let composerToolsScript = #"""
    (function () {
      'use strict';

      if (window.__zcsComposerTools) { return; }
      window.__zcsComposerTools = true;

      var PANEL = '[data-testid="prompt-suggestion-panel"]';
      var MODEL_TRIGGER = '[data-testid="chat-model-select-trigger"]';
      var SEND = '[data-testid="v4-composer-send"]';
      var ROW_ATTR = 'data-zcs-model-row';
      var ROW_LABEL_ATTR = 'data-zcs-model-label';
      var HOLD_MS = 500;
      var HOLD_SLOP = 10;
      var CLOSE_DELAY_MS = 120;

      function find(root, selector) {
        return root && root.querySelector ? root.querySelector(selector) : null;
      }

      function closestElement(node, selector) {
        if (!node || node.nodeType !== 1) { return null; }
        return node.closest ? node.closest(selector) : null;
      }

      function currentModelName() {
        var trigger = find(document, MODEL_TRIGGER);
        if (!trigger) { return ''; }
        var raw = trigger.innerText || trigger.textContent || '';
        return raw.replace(/\s+/g, ' ').trim();
      }

      function rowLabel(name) {
        return '模型 · ' + (name || '选择模型');
      }

      /// True only while dispatching our own model-picker tap. Those events
      /// bubble through document too, and must not be mistaken for the end of
      /// a real long press on send.
      var syntheticTap = false;

      /// Radix's trigger opens on pointerdown; a bare click() is ignored. Send
      /// the whole sequence at the element's centre, with the payload mobile
      /// WebKit would produce for a touch.
      function tapLikeTouch(el) {
        if (!el) { return; }
        var rect = el.getBoundingClientRect();
        var x = rect.left + rect.width / 2;
        var y = rect.top + rect.height / 2;
        var Ctor = window.PointerEvent || window.MouseEvent;

        function init(buttons, detail) {
          return {
            bubbles: true,
            cancelable: true,
            composed: true,
            view: window,
            detail: detail,
            clientX: x,
            clientY: y,
            screenX: x,
            screenY: y,
            pointerId: 1,
            pointerType: 'touch',
            isPrimary: true,
            button: 0,
            buttons: buttons
          };
        }

        syntheticTap = true;
        try {
          el.dispatchEvent(new Ctor('pointerdown', init(1, 0)));
          el.dispatchEvent(new Ctor('pointerup', init(0, 0)));
          el.dispatchEvent(new Ctor('click', init(0, 1)));
        } catch (e) {
          // The trigger may have been replaced mid-sequence; nothing to undo.
        } finally {
          syntheticTap = false;
        }
      }

      // The attachment panel and the model popover are siblings in the same
      // popper layer, so the first one has to be dismissed before the second
      // can anchor itself. Escape is what Radix listens for.
      var openingModel = false;
      function dismissPanelAndOpenModel() {
        if (openingModel) { return; }
        openingModel = true;

        var panel = find(document, PANEL);
        var target = document.activeElement;
        if (!target || !target.isConnected) {
          target = panel || document.body || document;
        }

        var keyInit = {
          key: 'Escape',
          code: 'Escape',
          keyCode: 27,
          which: 27,
          bubbles: true,
          cancelable: true,
          composed: true
        };
        try {
          target.dispatchEvent(new KeyboardEvent('keydown', keyInit));
          target.dispatchEvent(new KeyboardEvent('keyup', keyInit));
        } catch (e) {
          try { document.dispatchEvent(new KeyboardEvent('keydown', keyInit)); } catch (e2) {}
        }

        window.setTimeout(function () {
          openingModel = false;
          tapLikeTouch(find(document, MODEL_TRIGGER));
        }, CLOSE_DELAY_MS);
      }

      function styleRow(row, sample) {
        var s = row.style;
        s.display = 'flex';
        s.alignItems = 'center';
        s.boxSizing = 'border-box';
        s.width = '100%';
        s.minHeight = '40px';
        s.margin = '0';
        s.padding = '10px 12px';
        s.border = '0';
        s.borderRadius = '10px';
        s.background = 'transparent';
        s.color = 'inherit';
        s.fontFamily = 'inherit';
        s.fontSize = '14px';
        s.fontWeight = '400';
        s.lineHeight = '20px';
        s.textAlign = 'left';
        s.cursor = 'pointer';
        s.outline = 'none';
        s.webkitTapHighlightColor = 'transparent';
        s.transition = 'background-color 120ms ease';

        if (!sample) { return; }
        try {
          var cs = window.getComputedStyle(sample);
          if (!cs) { return; }
          if (cs.fontFamily) { s.fontFamily = cs.fontFamily; }
          if (cs.fontSize) { s.fontSize = cs.fontSize; }
          if (cs.fontWeight) { s.fontWeight = cs.fontWeight; }
          if (cs.lineHeight && cs.lineHeight !== 'normal') { s.lineHeight = cs.lineHeight; }
          if (cs.letterSpacing && cs.letterSpacing !== 'normal') { s.letterSpacing = cs.letterSpacing; }
          if (cs.color) { s.color = cs.color; }
          if (cs.borderRadius && cs.borderRadius !== '0px') { s.borderRadius = cs.borderRadius; }
          var padding = [cs.paddingTop, cs.paddingRight, cs.paddingBottom, cs.paddingLeft];
          if (padding.every(function (value) {
            var number = parseFloat(value);
            return isFinite(number) && number >= 0;
          })) {
            s.padding = padding.join(' ');
          }
          var height = sample.getBoundingClientRect().height;
          if (height > 0) { s.minHeight = Math.round(height) + 'px'; }
        } catch (e) {}
      }

      function bindPressFeedback(row) {
        function clear() { row.style.backgroundColor = 'transparent'; }
        row.addEventListener('pointerdown', function () {
          row.style.backgroundColor = 'rgba(127,127,127,0.16)';
        }, true);
        row.addEventListener('pointerup', clear, true);
        row.addEventListener('pointercancel', clear, true);
        row.addEventListener('pointerleave', clear, true);
      }

      function buildRow(name) {
        var row = document.createElement('button');
        row.type = 'button';
        row.setAttribute(ROW_ATTR, '');
        row.setAttribute(ROW_LABEL_ATTR, rowLabel(name));
        row.setAttribute('aria-label', rowLabel(name));

        var prefix = document.createElement('span');
        prefix.textContent = '模型 · ';
        prefix.style.opacity = '0.58';
        prefix.style.flex = '0 0 auto';

        var value = document.createElement('span');
        value.textContent = name || '选择模型';
        value.style.minWidth = '0';
        value.style.overflow = 'hidden';
        value.style.textOverflow = 'ellipsis';
        value.style.whiteSpace = 'nowrap';

        row.appendChild(prefix);
        row.appendChild(value);
        row.__zcsValue = value;

        // Capture so the panel's own click handling cannot run first and close
        // the panel before our Escape + delayed trigger sequence.
        row.addEventListener('click', function (event) {
          event.preventDefault();
          event.stopPropagation();
          dismissPanelAndOpenModel();
        }, true);

        bindPressFeedback(row);
        return row;
      }

      /// The first real row in the panel is both the insertion anchor and the
      /// style sample. If the panel is still empty, fall back to the panel.
      function firstRow(panel) {
        var groups = [
          '[role="menuitem"]',
          '[role="option"]',
          '[role="button"]',
          'button',
          'a[href]',
          'li'
        ];
        for (var g = 0; g < groups.length; g++) {
          var list = panel.querySelectorAll(groups[g]);
          for (var i = 0; i < list.length; i++) {
            var el = list[i];
            if (el.hasAttribute(ROW_ATTR)) { continue; }
            if (el.closest('[' + ROW_ATTR + ']')) { continue; }
            return el;
          }
        }
        return null;
      }

      function ensureRow() {
        var panel = find(document, PANEL);
        if (!panel) { return; }

        var name = currentModelName();
        var label = rowLabel(name);
        var row = panel.querySelector('[' + ROW_ATTR + ']');

        // Insert into the panel's scrollable list, not the panel root and not
        // beside the first row. The root sits outside the scroll area, and the
        // first row lives inside a group whose layout must not be disturbed.
        var list = panel.firstElementChild || panel;

        if (!row) {
          row = buildRow(name);
          styleRow(row, null);
          list.insertBefore(row, list.firstChild);
          return;
        }

        if (row.parentNode !== list || list.firstElementChild !== row) {
          styleRow(row, null);
          list.insertBefore(row, list.firstChild);
        }

        if (row.getAttribute(ROW_LABEL_ATTR) !== label) {
          row.setAttribute(ROW_LABEL_ATTR, label);
          row.setAttribute('aria-label', label);
          if (row.__zcsValue) { row.__zcsValue.textContent = name || '选择模型'; }
        }
      }

      var ensureScheduled = false;
      function scheduleEnsure() {
        if (ensureScheduled) { return; }
        ensureScheduled = true;
        // A timeout rather than requestAnimationFrame: the row only needs the
        // DOM, and rAF is paused while the web view is in the background.
        window.setTimeout(function () {
          ensureScheduled = false;
          try { ensureRow(); } catch (e) {}
        }, 0);
      }

      function watchPanel() {
        if (!window.MutationObserver) { return; }
        var observer = new MutationObserver(function () {
          // Fast path: no panel, nothing to do. The panel is mounted on open
          // and destroyed on close, so a single query per mutation batch is
          // enough and keeps streaming transcripts cheap.
          if (!find(document, PANEL)) { return; }
          scheduleEnsure();
        });
        observer.observe(document.documentElement, { childList: true, subtree: true });
      }

      // Long press on send. Listeners live at capture time on document because
      // the composer's button is re-rendered by React.
      var press = null;
      var suppressSendClick = false;
      var suppressReset = 0;

      function endPress() {
        if (press && press.timer) {
          window.clearTimeout(press.timer);
        }
        press = null;
      }

      // After a long press has fired, keep swallowing until the touch ends and
      // its click arrives (or 800 ms pass without one). A fixed timer from the
      // 500 ms mark would let an unusually long hold send on release.
      function scheduleSuppressReset() {
        if (!suppressSendClick) { return; }
        window.clearTimeout(suppressReset);
        suppressReset = window.setTimeout(function () {
          suppressSendClick = false;
        }, 800);
      }

      function onPressDown(event) {
        if (syntheticTap) { return; }
        if (event.isPrimary === false) { return; }
        if (event.pointerType === 'mouse' && event.button !== 0) { return; }
        if (!closestElement(event.target, SEND)) { return; }

        endPress();
        // A new press always starts unsuppressed, so a stale flag from a long
        // press whose click never arrived cannot eat a real send tap.
        suppressSendClick = false;
        window.clearTimeout(suppressReset);

        var pointerId = event.pointerId == null ? 1 : event.pointerId;
        press = {
          id: pointerId,
          x: event.clientX,
          y: event.clientY,
          timer: 0
        };
        press.timer = window.setTimeout(function () {
          if (!press) { return; }
          press.timer = 0;
          suppressSendClick = true;
          tapLikeTouch(find(document, MODEL_TRIGGER));
        }, HOLD_MS);
      }

      function onPressMove(event) {
        if (syntheticTap || !press) { return; }
        var pointerId = event.pointerId == null ? 1 : event.pointerId;
        if (pointerId !== press.id) { return; }
        var dx = event.clientX - press.x;
        var dy = event.clientY - press.y;
        if (dx * dx + dy * dy > HOLD_SLOP * HOLD_SLOP) {
          endPress();
          scheduleSuppressReset();
        }
      }

      function onPressUp(event) {
        if (syntheticTap || !press) { return; }
        var pointerId = event.pointerId == null ? 1 : event.pointerId;
        if (pointerId !== press.id) { return; }
        endPress();
        scheduleSuppressReset();
      }

      function onClickCapture(event) {
        if (!suppressSendClick) { return; }
        if (!closestElement(event.target, SEND)) { return; }
        event.preventDefault();
        event.stopPropagation();
        if (event.stopImmediatePropagation) { event.stopImmediatePropagation(); }
        suppressSendClick = false;
        window.clearTimeout(suppressReset);
      }

      function boot() {
        if (!document.documentElement) {
          window.setTimeout(boot, 16);
          return;
        }

        document.addEventListener('pointerdown', onPressDown, true);
        document.addEventListener('pointermove', onPressMove, true);
        document.addEventListener('pointerup', onPressUp, true);
        document.addEventListener('pointercancel', onPressUp, true);
        document.addEventListener('click', onClickCapture, true);
        window.addEventListener('blur', endPress, true);

        watchPanel();
        if (document.readyState === 'loading') {
          document.addEventListener('DOMContentLoaded', scheduleEnsure, { once: true });
        } else {
          scheduleEnsure();
        }
      }

      boot();
    })();
    """#

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
        // Route is known as soon as the document settles; don't wait for the
        // polling timer, which is what made the bar flash in late.
        pollRoute()
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

// MARK: - WKUIDelegate

extension WebModel: WKUIDelegate {
    /// Handles `<input type="file">` taps. Without this the page's attachment
    /// button silently does nothing. The parameters type is annotated iOS 18.4+
    /// in current SDKs, so the method only installs on those systems.
    @available(iOS 18.4, *)
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        guard let root = webView.window?.rootViewController else {
            completionHandler(nil)
            return
        }
        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        FilePicker.present(
            from: presenter,
            allowsMultiple: parameters.allowsMultipleSelection,
            completion: { [weak self] urls in
                if let urls, !urls.isEmpty {
                    let picked = urls.map { url in
                        PendingAttachment(url: url, image: UIImage(contentsOfFile: url.path))
                    }
                    DispatchQueue.main.async {
                        self?.attachments.append(contentsOf: picked)
                    }
                }
                completionHandler(urls)
            }
        )
    }
}

// MARK: - SwiftUI bridge

struct ZCodeWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
