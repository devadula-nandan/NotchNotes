import Cocoa
import WebKit

// MARK: - Window

final class NotchWindow: NSPanel {
    override var canBecomeKey: Bool { true }

    // Accessory apps have no Edit menu, so handle the standard shortcuts here
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command || flags == [.command, .shift],
              let key = event.charactersIgnoringModifiers?.lowercased()
        else { return super.performKeyEquivalent(with: event) }

        let actions: [String: Selector] = [
            "a": #selector(NSResponder.selectAll(_:)),
            "c": #selector(NSText.copy(_:)),
            "v": #selector(NSText.paste(_:)),
            "x": #selector(NSText.cut(_:)),
            "z": NSSelectorFromString(flags.contains(.shift) ? "redo:" : "undo:"),
            "q": #selector(NSApplication.terminate(_:)),
            "[": #selector(WKWebView.goBack(_:)),
            "]": #selector(WKWebView.goForward(_:)),
            "r": #selector(WKWebView.reload(_:)),
        ]
        guard let action = actions[key] else { return super.performKeyEquivalent(with: event) }
        return NSApp.sendAction(action, to: nil, from: self)
    }
}

// MARK: - Content view (hover, notch shape, panel placement)

final class NotchContentView: NSView {
    weak var wc: NotchWindowController?
    weak var panel: NSView?
    private let shapeMask = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.mask = shapeMask
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let wc else { return }
        let w = bounds.width, h = bounds.height

        // Panel stays full-size, centered and pinned to the top; the window just reveals it
        panel?.frame = CGRect(x: (w - wc.panelW) / 2, y: h - wc.panelH, width: wc.panelW, height: wc.panelH)

        // Notch shape: inverted top corners, rounded bottom
        let r = shapeRadius(height: h, fullHeight: wc.panelH)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: h))
        p.addQuadCurve(to: CGPoint(x: r, y: h - r), control: CGPoint(x: r, y: h))
        p.addLine(to: CGPoint(x: r, y: r))
        p.addQuadCurve(to: CGPoint(x: 2 * r, y: 0), control: CGPoint(x: r, y: 0))
        p.addLine(to: CGPoint(x: w - 2 * r, y: 0))
        p.addQuadCurve(to: CGPoint(x: w - r, y: r), control: CGPoint(x: w - r, y: 0))
        p.addLine(to: CGPoint(x: w - r, y: h - r))
        p.addQuadCurve(to: CGPoint(x: w, y: h), control: CGPoint(x: w - r, y: h))
        p.closeSubpath()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeMask.frame = bounds
        shapeMask.path = p
        CATransaction.commit()

        wc.clipWebView()
    }

    // Leaving is detected by the controller's poll while the panel is open
    override func mouseEntered(with event: NSEvent) {
        guard let wc else { return }
        // A locked-open panel loses focus when another app is clicked; take it back on hover
        if wc.isExpanded, window?.isKeyWindow == false { window?.makeKey() }
        wc.expand()
    }
}

// MARK: - Window controller

final class NotchWindowController: NSWindowController {
    private(set) var isExpanded = false
    private(set) var panelW = stored("panelW", default: 500)
    private(set) var panelH = stored("panelH", default: 280)
    private var fontSize = stored("fontSize", default: 13)
    private var webURL = UserDefaults.standard.string(forKey: "webURL") ?? "" {
        didSet { UserDefaults.standard.set(webURL, forKey: "webURL") }
    }
    private var hiddenFromCapture = true { didSet { applyCapture() } }
    private var isLocked = false { didSet { applyLock() } }      // a locked panel stays open when the mouse leaves
    private var mobileAgent = UserDefaults.standard.bool(forKey: "mobileAgent") {
        didSet { UserDefaults.standard.set(mobileAgent, forKey: "mobileAgent"); applyAgent(reload: true) }
    }
    private var animationID = 0                                  // ignores completions from interrupted animations

    private let panel = NSView()
    private let scrollView = NSScrollView()
    private let textView = NoteTextView()
    private var webView: WKWebView?
    private var popups: [WKWebView] = []                         // windows the page opened, topmost last
    private var webObservations: [ObjectIdentifier: [NSKeyValueObservation]] = [:]
    private var themeObservation: NSKeyValueObservation?
    private let webHost = NSView()                               // holds the page and its pop-ups, clipped to the panel's shape
    private let webMask = CAShapeLayer()
    private let loadingPill = LoadingPill(frame: .zero)

    private let quitButton = IconButton("circle.fill", hint: "Quit")
    private let lockButton = IconButton("lock.open.fill", hint: "")
    private let captureButton = IconButton("eye.slash.fill", hint: "")
    private let moreButton = IconButton("ellipsis", hint: "More")
    private let checklistButton = IconButton("checklist", hint: "Checklist")
    private let numberedButton = IconButton("list.number", hint: "Numbered List")
    private let agentButton = IconButton("desktopcomputer", hint: "")
    private let clearButton = IconButton("xmark.circle.fill", hint: "Close Page", width: clearW)
    private lazy var sizeField = FontSizeField(value: fontSize, range: 10...24)
    private let urlBox = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: toolH))
    private let urlField = FadingField(frame: .zero)
    private let tray = NSView()
    private let hintView = NSView()
    private let hintLabel = NSTextField(labelWithString: "")

    private var hintTimer: Timer?
    private var saveTimer: Timer?
    private var hoverTimer: Timer?

    // Formatting tools, left of the notch; they overflow into the tray from the last one
    private var formatTools: [NSView] { [checklistButton, numberedButton, sizeField] }

    private var allWebViews: [WKWebView] { (webView.map { [$0] } ?? []) + popups }
    private var shownWeb: WKWebView? { popups.last ?? webView }
    private var shownAddress: String { popups.last.map { $0.url?.absoluteString ?? "" } ?? webURL }

    var panelSize: CGSize { CGSize(width: panelW, height: panelH) }

    // Padded by 1pt: CGRect.contains excludes the max edges, and the cursor sits
    // exactly on the top edge at the top of the screen, which made hover flicker
    private var isMouseInside: Bool {
        (isExpanded ? expandedFrame : collapsedFrame).insetBy(dx: -1, dy: -1).contains(NSEvent.mouseLocation)
    }

    private var collapsedFrame: CGRect {
        let s = notchScreen.frame, n = notchSize, w = n.width + 2 * collapsedRadius
        return CGRect(x: s.midX - w / 2, y: s.maxY - n.height, width: w, height: n.height)
    }

    private var expandedFrame: CGRect {
        let s = notchScreen.frame, w = panelW + 2 * expandedRadius
        return CGRect(x: s.midX - w / 2, y: s.maxY - panelH, width: w, height: panelH)
    }

    private func clamped(_ size: CGSize) -> CGSize {
        // Each side of the notch must fit two buttons: quit + lock on the left, "…" + eye on the right
        let s = notchScreen.frame, n = notchSize, side = edgeInset + 2 * toolW + toolGap + notchGap
        return CGSize(width: min(max(size.width, n.width + 2 * side), s.width - 2 * expandedRadius - 40).rounded(),
                      height: min(max(size.height, n.height + 46), s.height * 0.9).rounded())
    }

    convenience init() {
        let win = NotchWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.level = NSWindow.Level(rawValue: topLevel)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.ignoresMouseEvents = false   // keep receiving hover while fully transparent
        win.hasShadow = false
        win.hidesOnDeactivate = false
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.init(window: win)
    }

    // MARK: - Building the UI

    func buildUI() {
        guard let win = window else { return }
        let size = clamped(panelSize)
        panelW = size.width
        panelH = size.height
        win.setFrame(expandedFrame, display: false)

        let cv = NotchContentView(frame: CGRect(origin: .zero, size: expandedFrame.size))
        cv.wc = self
        win.contentView = cv

        buildNotes()
        buildToolbar()
        buildOverlays()

        panel.frame = CGRect(x: 0, y: 0, width: panelW, height: panelH)
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor.black.cgColor
        webHost.wantsLayer = true
        webHost.layer?.mask = webMask
        [scrollView, webHost, loadingPill, quitButton, lockButton, captureButton, moreButton].forEach(panel.addSubview)
        for right in [false, true] {
            let grip = ResizeHandle(right: right)
            grip.wc = self
            if right {
                grip.frame.origin.x = panelW - grip.frame.width
                grip.autoresizingMask = [.minXMargin]
            }
            panel.addSubview(grip)
        }
        [tray, hintView].forEach(panel.addSubview)
        cv.addSubview(panel)
        cv.panel = panel

        applyCapture()
        applyLock()
        applyAgent(reload: false)
        updateListButtons()
        setWebURL(webURL)   // also lays out the controls

        // The panel is forced dark, but web pages follow the system light/dark setting
        themeObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.applySystemTheme() }
        }

        // Start collapsed and fully transparent
        win.setFrame(collapsedFrame, display: false)
        cv.alphaValue = 0

        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.stayInFront() }
    }

    // Notes (text area sits below the notch so nothing hides behind the camera)
    private func buildNotes() {
        scrollView.hasVerticalScroller = true
        scrollView.backgroundColor = .black

        textView.autoresizingMask = [.width]
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.backgroundColor = .black
        textView.insertionPointColor = NSColor(white: 0.7, alpha: 1)
        // No foreground override: it would reveal the hidden "- [ ]" behind checkboxes
        textView.selectedTextAttributes = [.backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.5)]
        textView.textContainerInset = CGSize(width: 10, height: 6)   // 2pt above the text, 10pt below (see textContainerOrigin)
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.string = (try? String(contentsOf: notesURL, encoding: .utf8)) ?? ""
        textView.restyle()
        textView.onChange = { [weak self] in self?.scheduleSave(); self?.updateListButtons() }
        NotificationCenter.default.addObserver(self, selector: #selector(updateListButtons),
                                               name: NSTextView.didChangeSelectionNotification, object: textView)
        scrollView.documentView = textView
        scrollView.documentCursor = .arrow
    }

    private func buildToolbar() {
        quitButton.iconColor = NSColor(red: 1, green: 0.37, blue: 0.37, alpha: 1)
        quitButton.hoverFill = .clear
        quitButton.hoverSymbol = "xmark.circle.fill"   // like the window close button: an × appears on hover
        quitButton.onClick = { NSApp.terminate(nil) }

        lockButton.tint = .systemYellow
        lockButton.onClick = { [weak self] in self?.isLocked.toggle() }

        captureButton.tint = .systemOrange
        captureButton.onClick = { [weak self] in self?.hiddenFromCapture.toggle() }

        checklistButton.tint = .systemGreen
        checklistButton.onClick = { [weak self] in self?.textView.toggleList(.checkbox) }
        numberedButton.tint = .systemBlue
        numberedButton.onClick = { [weak self] in self?.textView.toggleList(.numbered) }

        agentButton.isActive = true
        agentButton.onClick = { [weak self] in self?.mobileAgent.toggle() }

        sizeField.onChange = { [weak self] in self?.setFontSize($0) }
        sizeField.onReturn = { [weak self] in self?.window?.makeFirstResponder(self?.textView) }

        moreButton.onClick = { [weak self] in
            guard let self else { return }
            self.tray.isHidden.toggle()
            self.moreButton.isActive = !self.tray.isHidden
        }

        // URL field: Return loads the page (or searches), empty + Return goes back to notes
        urlBox.wantsLayer = true
        urlBox.layer?.cornerRadius = 6
        urlField.frame = urlBox.bounds.insetBy(dx: 6, dy: 0)
        urlField.autoresizingMask = [.width, .height]
        urlField.placeholderString = "Search or URL"
        urlField.target = self
        urlField.action = #selector(urlEntered)
        urlBox.addSubview(urlField)

        // Clear button at the right end of the URL field, shown while a page is loaded
        clearButton.frame.origin.x = urlBox.bounds.width - clearW - 2
        clearButton.autoresizingMask = [.minXMargin]
        clearButton.hoverFill = .clear
        clearButton.onClick = { [weak self] in
            guard let self else { return }
            if let popup = self.popups.last { return self.closePopup(popup) }
            self.urlField.reset(to: "")
            self.setWebURL("")
            self.closeTray()
            self.window?.makeFirstResponder(self.textView)
        }
        urlBox.addSubview(clearButton)

        for b in [quitButton, lockButton, captureButton, moreButton, checklistButton, numberedButton, agentButton, clearButton] {
            b.onHover = { [weak self, weak b] on in
                if let self, let b { self.hover(b, on) }
            }
        }
    }

    private func buildOverlays() {
        // Overflow tray for controls that don't fit beside the notch
        tray.wantsLayer = true
        tray.layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
        tray.layer?.cornerRadius = 8
        tray.isHidden = true

        // Clicking anywhere outside the open tray (or its "…" button) closes it
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, !self.tray.isHidden, event.window === self.window else { return event }
            let inside = [self.tray, self.moreButton].contains { $0.bounds.contains($0.convert(event.locationInWindow, from: nil)) }
            if !inside { self.closeTray() }
            return event
        }

        // In-panel hint (system tooltips use their own window and leak into screen shares)
        hintLabel.font = .systemFont(ofSize: 11, weight: .medium)
        hintLabel.textColor = inkColor
        hintView.wantsLayer = true
        hintView.layer?.backgroundColor = NSColor(white: 0.18, alpha: 1).cgColor
        hintView.layer?.cornerRadius = 5
        hintView.addSubview(hintLabel)
        hintView.isHidden = true
    }

    // MARK: - Layout

    private func layoutControls() {
        // Content: notes or web page, below the notch
        let contentH = panelH - notchSize.height
        scrollView.frame = CGRect(x: 0, y: 0, width: panelW, height: contentH)
        webHost.frame = scrollView.frame.insetBy(dx: webInset, dy: webInset)
        clearButton.hint = popups.isEmpty ? "Close Page" : "Close Pop-up"
        textView.minSize = CGSize(width: 0, height: scrollView.contentSize.height)
        textView.frame.size.width = scrollView.contentSize.width
        clipWebView()

        // Top strip. Fixed: quit and lock at the left edge, eye at the right, "…" beside it when needed
        let y = panelH - notchSize.height / 2 - toolH / 2, step = toolW + toolGap
        let eyeX = panelW - edgeInset - toolW, moreX = eyeX - step
        quitButton.frame.origin = CGPoint(x: edgeInset, y: y)
        lockButton.frame.origin = CGPoint(x: edgeInset + step, y: y)
        captureButton.frame.origin = CGPoint(x: eyeX, y: y)
        moreButton.frame.origin = CGPoint(x: moreX, y: y)

        // Re-parent only when needed, so a field being edited isn't interrupted
        func place(_ v: NSView, in parent: NSView, x: CGFloat, y: CGFloat) {
            if v.superview !== parent { parent.addSubview(v, positioned: .below, relativeTo: parent === panel ? tray : nil) }
            v.frame.origin = CGPoint(x: x, y: y)
        }
        func rowWidth(_ views: [NSView]) -> CGFloat {
            views.reduce(0) { $0 + $1.frame.width } + CGFloat(max(views.count - 1, 0)) * toolGap
        }

        // Each side of the notch has the same space. The formatting tools only apply to notes and the
        // agent button only to a page (where it sits just left of the URL field), so only one is shown at a time
        let side = (panelW - notchSize.width) / 2, toolsX = edgeInset + 2 * step
        let web = webView != nil
        formatTools.forEach { $0.isHidden = web }
        agentButton.isHidden = !web

        // Tools stay beside the notch while they fit; the rest move into the tray, last one first
        var x = toolsX, overflow: [NSView] = []
        for v in web ? [] : formatTools {
            if overflow.isEmpty, x + v.frame.width + notchGap <= side {
                place(v, in: panel, x: x, y: y)
                x += v.frame.width + toolGap
            } else {
                overflow.append(v)
            }
        }

        // The URL field takes what's left on the right, after the eye and (once anything overflows) "…".
        // Its minimum is the width it has at the moment the first tool overflows, so the two go together
        let rightFixed = edgeInset + step + notchGap
        let urlMinW = toolsX + rowWidth(formatTools) + notchGap - rightFixed - step
        let urlRoom = side - rightFixed - (overflow.isEmpty ? 0 : step) - (web ? step : 0)
        if urlRoom >= urlMinW {
            urlBox.frame.size.width = urlRoom.rounded(.down)
            place(urlBox, in: panel, x: (overflow.isEmpty ? eyeX : moreX) - toolGap - urlBox.frame.width, y: y)
            if web { place(agentButton, in: panel, x: urlBox.frame.minX - step, y: y) }
        } else {
            if web { overflow.append(agentButton) }
            overflow.append(urlBox)
        }

        moreButton.isHidden = overflow.isEmpty
        guard !overflow.isEmpty else { return closeTray() }

        // The tray spans the panel below the top strip; an overflowed URL field takes the width the tools leave
        let w = panelW - 2 * edgeInset, h = toolH + 2 * trayPad
        tray.frame = CGRect(x: edgeInset, y: y - 6 - h, width: w, height: h)
        if overflow.last === urlBox {
            let others = Array(overflow.dropLast())
            urlBox.frame.size.width = w - 2 * trayPad - (others.isEmpty ? 0 : rowWidth(others) + toolGap)
        }
        x = trayPad
        for v in overflow {
            place(v, in: tray, x: x, y: trayPad)
            x += v.frame.width + toolGap
        }
    }

    private func closeTray() {
        tray.isHidden = true
        moreButton.isActive = false
    }

    // Clip the web page to the visible part of the notch shape, inset by the border,
    // so the black border follows the shape while it expands and collapses
    func clipWebView() {
        guard webView != nil, let size = window?.contentView?.bounds.size else { return }
        let r = shapeRadius(height: size.height, fullHeight: panelH)

        // Visible body of the notch shape (excluding the flared top corners), in panel coordinates
        let originX = (size.width - panelW) / 2, originY = size.height - panelH
        let body = CGRect(x: r - originX, y: -originY, width: size.width - 2 * r, height: size.height)
            .insetBy(dx: webInset, dy: webInset)
        let visible = body.intersection(webHost.frame)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        webMask.frame = webHost.bounds
        if visible.isNull || visible.isEmpty {
            webMask.path = CGPath(rect: .zero, transform: nil)
        } else {
            let rect = webHost.convert(visible, from: panel)
            let cr = min(max(r - webInset, 0), rect.width / 2, rect.height / 2)
            // The inward curve only exists while the corner is gentler than the border is thick
            // (early in the expand animation it isn't; a plain rounded rect is fine for those frames)
            if r / 2.squareRoot() > webInset + 1, visible.width > 2 * r, visible.height > r + cr {
                let v = visible, d = webInset
                let curve = cornerCurve(radius: r, inset: d).map { CGPoint(x: v.minX - d + $0.x, y: v.minY - d + $0.y) }
                let path = CGMutablePath()
                path.move(to: CGPoint(x: v.minX, y: v.maxY - cr))
                curve.forEach { path.addLine(to: $0) }
                curve.reversed().forEach { path.addLine(to: CGPoint(x: v.minX + v.maxX - $0.x, y: $0.y)) }
                path.addLine(to: CGPoint(x: v.maxX, y: v.maxY - cr))
                path.addArc(tangent1End: CGPoint(x: v.maxX, y: v.maxY), tangent2End: CGPoint(x: v.maxX - cr, y: v.maxY), radius: cr)
                path.addLine(to: CGPoint(x: v.minX + cr, y: v.maxY))
                path.addArc(tangent1End: CGPoint(x: v.minX, y: v.maxY), tangent2End: CGPoint(x: v.minX, y: v.maxY - cr), radius: cr)
                path.closeSubpath()
                // Panel coordinates → the web area's
                let o = webHost.convert(CGPoint.zero, from: panel)
                var t = CGAffineTransform(translationX: o.x, y: o.y)
                webMask.path = path.copy(using: &t)
            } else {
                webMask.path = CGPath(roundedRect: rect, cornerWidth: cr, cornerHeight: cr, transform: nil)
            }
            // Loading pill sits in the black border under the page, between its rounded corners
            loadingPill.setTrack(center: CGPoint(x: visible.midX, y: visible.minY - webInset / 2),
                                 maxWidth: visible.width - 2 * cr)
        }
        CATransaction.commit()
    }

    // Show a button's hint under it after a short hover
    private func hover(_ b: IconButton, _ on: Bool) {
        hintTimer?.invalidate()
        hintView.isHidden = true
        guard on else { return }
        hintTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self, weak b] _ in
            guard let self, let b, b.window != nil else { return }
            self.showHint(b.hint, under: b.convert(b.bounds, to: self.panel))
        }
    }

    private func showHint(_ text: String, under a: CGRect) {
        hintLabel.stringValue = text
        let ls = hintLabel.fittingSize
        let w = ls.width + 12, h = ls.height + 6
        hintView.frame = CGRect(x: min(max(a.midX - w / 2, 6), panelW - w - 6), y: a.minY - 6 - h, width: w, height: h)
        hintLabel.frame = CGRect(x: 6, y: 3, width: ls.width, height: ls.height)
        hintView.isHidden = false
    }

    // A short notice under the notch (downloads)
    private func flash(_ text: String) {
        hintTimer?.invalidate()
        showHint(text, under: CGRect(x: panelW / 2, y: panelH - notchSize.height + 2, width: 0, height: 0))
        hintTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.hintView.isHidden = true
        }
    }

    // Keyboard focus goes to the page (or its pop-up), else the notes
    private func focusContent() {
        window?.makeFirstResponder(shownWeb ?? textView)
    }

    // MARK: - Web page

    @objc private func urlEntered() {
        setWebURL(urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        closeTray()
        focusContent()
    }

    // What was typed is an address if it looks like one (scheme, dotted host, localhost); otherwise a Google search
    private func destination(for text: String) -> URL? {
        if text.contains("://") { return URL(string: text) }
        let host = text.prefix { $0 != "/" && $0 != ":" && $0 != "?" }
        let looksLikeAddress = !text.contains(" ") && (host.contains(".") || host == "localhost")
        if looksLikeAddress, let url = URL(string: "https://" + text) { return url }
        var search = URLComponents(string: "https://www.google.com/search")
        search?.queryItems = [URLQueryItem(name: "q", value: text)]
        return search?.url
    }

    // Non-empty text shows a web page (or a search for it); empty returns to the notes
    private func setWebURL(_ text: String) {
        popups.forEach(discard)
        popups = []
        if !text.isEmpty, let url = destination(for: text) {
            (webView ?? makeWebView()).load(URLRequest(url: url))
            webURL = text
        } else {
            closeWebView()
            webURL = ""
        }
        scrollView.isHidden = webView != nil
        webHost.isHidden = webView == nil
        webView?.isHidden = false
        clearButton.isHidden = webView == nil
        urlBox.layer?.backgroundColor = NSColor(white: 1, alpha: webView == nil ? 0.08 : 0.16).cgColor
        urlField.stringValue = webURL
        urlField.updateFades()
        urlField.frame.size.width = urlBox.bounds.width - 12 - (webView == nil ? 0 : clearW)
        layoutControls()
    }

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        // Keep the arrow over links, text and inputs in the page too
        config.userContentController.addUserScript(WKUserScript(
            source: "const s = document.createElement('style'); s.textContent = '* { cursor: default !important; }'; document.documentElement.appendChild(s);",
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        // Identify as Safari (the embedded engine omits this), so sites serve the same pages Safari gets
        config.applicationNameForUserAgent = "Version/\(safariVersion) Safari/605.1.15"

        let wv = WKWebView(frame: .zero, configuration: config)
        webView = wv
        adopt(wv)
        return wv
    }

    // Set-up shared by the page and its pop-ups
    private func adopt(_ wv: WKWebView) {
        wv.customUserAgent = mobileAgent ? mobileUserAgent : nil
        wv.underPageBackgroundColor = .black
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        wv.frame = webHost.bounds
        wv.autoresizingMask = [.width, .height]
        webHost.addSubview(wv)
        applySystemTheme()

        // Loading pill follows the load; the URL field follows the page actually being shown
        let progress: (WKWebView) -> Void = { [weak self] wv in
            guard let self, wv === self.shownWeb else { return }
            self.loadingPill.setProgress(wv.isLoading ? wv.estimatedProgress : nil)
        }
        webObservations[ObjectIdentifier(wv)] = [wv.observe(\.estimatedProgress) { wv, _ in progress(wv) },
                                                 wv.observe(\.isLoading) { wv, _ in progress(wv) },
                                                 wv.observe(\.url) { [weak self] wv, _ in self?.pageURLChanged(wv) }]
    }

    // A window the page opens from script (sign-in pop-ups mostly) covers the page until it closes itself or
    // is closed with the × in the URL field. The page stays loaded underneath, so the two can still talk
    private func openPopup(_ configuration: WKWebViewConfiguration) -> WKWebView {
        let wv = WKWebView(frame: .zero, configuration: configuration)
        popups.append(wv)
        adopt(wv)
        showTopWeb()
        return wv
    }

    private func closePopup(_ wv: WKWebView) {
        guard let i = popups.firstIndex(of: wv) else { return }
        popups.remove(at: i)
        discard(wv)
        showTopWeb()
    }

    // Only the topmost web view is visible; the URL field, its × and the loading pill follow it
    private func showTopWeb() {
        let top = shownWeb
        for wv in allWebViews where wv !== top { wv.isHidden = true }
        top?.isHidden = false
        urlField.reset(to: shownAddress)
        loadingPill.reset()
        if let top, top.isLoading { loadingPill.setProgress(top.estimatedProgress) }
        layoutControls()
        focusContent()
    }

    private func discard(_ wv: WKWebView) {
        webObservations[ObjectIdentifier(wv)] = nil
        wv.navigationDelegate = nil          // a load still in flight must not report back after closing
        wv.stopLoading()
        wv.removeFromSuperview()
    }

    private func closeWebView() {
        allWebViews.forEach(discard)
        popups = []
        webView = nil
        loadingPill.reset()
    }

    private func pageURLChanged(_ wv: WKWebView) {
        guard let url = wv.url, url.scheme == "http" || url.scheme == "https" else { return }
        if wv === webView { webURL = url.absoluteString }
        if wv === shownWeb, urlField.currentEditor() == nil {
            urlField.stringValue = url.absoluteString
            urlField.updateFades()
        }
    }

    // Web pages see the system's light/dark setting via prefers-color-scheme
    private func applySystemTheme() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        allWebViews.forEach { $0.appearance = NSAppearance(named: dark ? .darkAqua : .aqua) }
    }

    private var safariVersion: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return os >= 26 ? "\(os).0" : "18.5"
    }

    // iPhone Safari, so sites serve their mobile pages; nil falls back to the desktop Safari agent.
    // Like Safari itself from iOS 26 on, the OS version stays at 18_6 and only Version/ moves on
    private var mobileUserAgent: String {
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) "
            + "Version/\(safariVersion) Mobile/15E148 Safari/604.1"
    }

    // MARK: - Toggles, lists and font

    // The button shows the agent in use; the open page is reloaded so the site sees the new one
    private func applyAgent(reload: Bool) {
        agentButton.symbol = mobileAgent ? "iphone" : "desktopcomputer"
        agentButton.hint = mobileAgent ? "Switch to Desktop Site" : "Switch to Mobile Site"
        agentButton.tint = mobileAgent ? .systemPurple : .systemTeal
        guard let wv = webView else { return }
        allWebViews.forEach { $0.customUserAgent = mobileAgent ? mobileUserAgent : nil }
        guard reload else { return }
        // A service worker the page installed under the other agent answers the reload itself, with that
        // agent's page, so the page's workers are dropped first
        let dropWorkers = "if (navigator.serviceWorker) for (const r of await navigator.serviceWorker.getRegistrations()) await r.unregister();"
        wv.callAsyncJavaScript(dropWorkers, arguments: [:], in: nil, in: .page) { [weak self, weak wv] _ in
            guard let self, let wv, wv === self.webView else { return }
            wv.reloadFromOrigin()   // skip the cache: it holds the other agent's copy of the page
        }
    }

    private func applyCapture() {
        window?.sharingType = hiddenFromCapture ? .none : .readOnly
        captureButton.symbol = hiddenFromCapture ? "eye.slash.fill" : "eye.fill"
        captureButton.hint = hiddenFromCapture ? "Show in Screen Capture" : "Hide from Screen Capture"
        captureButton.isActive = !hiddenFromCapture
    }

    private func applyLock() {
        lockButton.symbol = isLocked ? "lock.fill" : "lock.open.fill"
        lockButton.hint = isLocked ? "Unlock" : "Keep Open"
        lockButton.isActive = isLocked
    }

    // Highlight the list button matching the line the caret is on
    @objc private func updateListButtons() {
        let kind = textView.listKindAtCaret
        checklistButton.isActive = kind == .checkbox
        numberedButton.isActive = kind == .numbered
    }

    private func setFontSize(_ size: CGFloat) {
        fontSize = size
        textView.font = .monospacedSystemFont(ofSize: size, weight: .regular)
        textView.restyle()
        store(size, "fontSize")
    }

    // Teams' share border also sits at the max level; re-order on top if anything there is in front of us
    private func stayInFront() {
        guard let win = window,
              let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        else { return }
        for info in list {
            if info[kCGWindowNumber as String] as? Int == win.windowNumber { return }
            if (info[kCGWindowLayer as String] as? Int ?? 0) >= topLevel {
                win.orderFrontRegardless()
                return
            }
        }
    }

    // MARK: - Resize

    func resizePanel(to size: CGSize) {
        let s = clamped(size)
        guard s != panelSize, isExpanded else { return }
        panelW = s.width
        panelH = s.height
        hintView.isHidden = true
        window?.setFrame(expandedFrame, display: true)
        layoutControls()
    }

    func savePanelSize() {
        store(panelW, "panelW")
        store(panelH, "panelH")
    }

    // MARK: - Expand / collapse

    // Appear instantly at notch size, then expand
    func expand() {
        guard !isExpanded, let win = window else { return }
        isExpanded = true
        animationID += 1
        let id = animationID
        stayInFront()
        win.contentView?.alphaValue = 1

        // Collapse once the cursor is outside with no button held (so not mid-resize or mid-selection).
        // Polled rather than driven by mouse-exit events: a quick hover in and out can leave before the
        // growing window reaches the cursor, and then no exit event ever fires
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, NSEvent.pressedMouseButtons == 0, !self.isMouseInside else { return }
            self.collapse()
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            win.animator().setFrame(expandedFrame, display: true)
        } completionHandler: { [weak self] in
            guard let self, self.animationID == id else { return }
            win.makeKeyAndOrderFront(nil)
            self.focusContent()
        }
    }

    // Shrink back to the notch, then fade out
    private func collapse() {
        guard isExpanded, !isLocked, let win = window, win.attachedSheet == nil else { return }
        hoverTimer?.invalidate()
        isExpanded = false
        animationID += 1
        let id = animationID
        hintView.isHidden = true
        closeTray()
        urlField.reset(to: shownAddress)   // drop unsubmitted edits
        sizeField.cancel()
        win.resignKey()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            win.animator().setFrame(collapsedFrame, display: true)
        } completionHandler: { [weak self] in
            guard self?.animationID == id else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                win.contentView?.animator().alphaValue = 0
            }
        }
    }

    // MARK: - Saving

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in self?.saveNow() }
    }

    func saveNow() {
        try? textView.string.write(to: notesURL, atomically: true, encoding: .utf8)
    }
}

// MARK: - Web view delegates

extension NotchWindowController: WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView === shownWeb else { return }
        loadingPill.reset()
        loadingPill.setProgress(webView.estimatedProgress)
    }

    // Only a page that never arrived counts as a failure: the address couldn't be reached at all
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let e = error as NSError
        guard webView === shownWeb, e.domain == NSURLErrorDomain, e.code != NSURLErrorCancelled else { return }
        loadingPill.setFailed()
    }

    // MARK: Pop-ups

    // Links that ask for a new tab or window (target="_blank") open in the panel instead.
    // Windows opened from script get a real web view, so the page that opened them can hear back
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        if navigationAction.navigationType == .linkActivated {
            webView.load(navigationAction.request)
            return nil
        }
        return openPopup(configuration)
    }

    func webViewDidClose(_ webView: WKWebView) { closePopup(webView) }

    // MARK: Dialogs

    // Attached to the panel as a sheet: on its own, an alert would open behind the panel, which sits above
    // every other window. It is a window of its own, so it is given the panel's screen-capture setting
    private func ask(_ message: String, input: String? = nil, cancel: Bool = false,
                     done: @escaping (_ ok: Bool, _ text: String?) -> Void) {
        guard let win = window else { return done(false, nil) }
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        if cancel { alert.addButton(withTitle: "Cancel") }
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 240, height: 22))
        if let input {
            field.stringValue = input
            alert.accessoryView = field
            alert.window.initialFirstResponder = field
        }
        alert.window.sharingType = win.sharingType
        NSApp.activate(ignoringOtherApps: true)
        alert.beginSheetModal(for: win) { response in
            let ok = response == .alertFirstButtonReturn
            done(ok, ok && input != nil ? field.stringValue : nil)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        ask(message) { _, _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        ask(message, cancel: true) { ok, _ in completionHandler(ok) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        ask(prompt, input: defaultText ?? "", cancel: true) { _, text in completionHandler(text) }
    }

    // File inputs
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let chooser = NSOpenPanel()
        chooser.allowsMultipleSelection = parameters.allowsMultipleSelection
        chooser.canChooseDirectories = parameters.allowsDirectories
        NSApp.activate(ignoringOtherApps: true)
        chooser.begin { completionHandler($0 == .OK ? chooser.urls : nil) }
    }

    // MARK: Downloads

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }

    // Anything sent as an attachment, or that the web view can't display, is saved instead
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")
        let attachment = disposition?.lowercased().hasPrefix("attachment") ?? false
        decisionHandler(attachment || !navigationResponse.canShowMIMEType ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    // Saved into Downloads, numbered if the name is taken
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let name = suggestedFilename as NSString
        var url = folder.appendingPathComponent(suggestedFilename), n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let numbered = "\(name.deletingPathExtension) \(n)"
            url = folder.appendingPathComponent(name.pathExtension.isEmpty ? numbered : "\(numbered).\(name.pathExtension)")
            n += 1
        }
        flash("Downloading \(url.lastPathComponent)")
        completionHandler(url)
    }

    func downloadDidFinish(_ download: WKDownload) { flash("Saved to Downloads") }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) { flash("Download failed") }
}
