import Cocoa
import WebKit
import NotchNotesCore

// MARK: - Window

final class NotchWindow: NSPanel {
    override var canBecomeKey: Bool { true }

    // Accessory apps have no Edit menu, so handle the standard shortcuts here
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command || flags == [.command, .shift],
              let key = event.charactersIgnoringModifiers?.lowercased()
        else { return super.performKeyEquivalent(with: event) }

        // ⌘L, ⌘N and ⌘⇧[ / ⌘⇧] belong to the panel itself
        if let wc = windowController as? NotchWindowController, wc.handleShortcut(key) { return true }

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

    // Esc closes the panel from the notes and drops an edit in the URL or size field; a web page keeps it for itself
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53,
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
           let wc = windowController as? NotchWindowController, wc.handleEscape() { return }
        super.sendEvent(event)
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
        wc.hoverBegan()
    }
}

// MARK: - Window controller

final class NotchWindowController: NSWindowController {
    private(set) var isExpanded = false
    private(set) var panelW = stored("panelW", default: 500)
    private(set) var panelH = stored("panelH", default: 280)
    private var fontSize = stored("fontSize", default: 13)
    var webURL = UserDefaults.standard.string(forKey: "webURL") ?? "" {
        didSet { UserDefaults.standard.set(webURL, forKey: "webURL") }
    }
    private var hiddenFromCapture = true { didSet { applyCapture() } }
    // A locked panel stays open when the mouse leaves
    private var isLocked = UserDefaults.standard.bool(forKey: "locked") {
        didSet { UserDefaults.standard.set(isLocked, forKey: "locked"); applyLock() }
    }
    private var keyboardOpened = false                           // opened by the hotkey: stays until the mouse has visited
    var mobileAgent = UserDefaults.standard.bool(forKey: "mobileAgent") {
        didSet { UserDefaults.standard.set(mobileAgent, forKey: "mobileAgent"); applyAgent(reload: true) }
    }
    private var animationID = 0                                  // ignores completions from interrupted animations

    private let panel = NSView()
    let scrollView = NSScrollView()
    let textView = NoteTextView()
    var webView: WKWebView?
    var popups: [WKWebView] = []                                 // windows the page opened, topmost last
    var webObservations: [ObjectIdentifier: [NSKeyValueObservation]] = [:]
    private var themeObservation: NSKeyValueObservation?
    let webHost = NSView()                                       // holds the page and its pop-ups, clipped to the panel's shape
    private let webMask = CAShapeLayer()
    let loadingPill = LoadingPill(frame: .zero)
    private let soundLine = NSImageView()

    private let notes = NoteStore(folder: notesFolder)
    private var noteIndex = 0
    private var noteUnreadable = false                           // its file couldn't be read, so it is never saved over
    private var notesDirty = false
    private var saveFailed = false
    private let pager = NotePager()

    private let quitButton = IconButton("circle.fill", hint: "Quit")
    private let lockButton = IconButton("lock.open.fill", hint: "")
    private let captureButton = IconButton("eye.slash.fill", hint: "")
    private let moreButton = IconButton("ellipsis", hint: "More")
    private let checklistButton = IconButton("checklist", hint: "Checklist")
    private let numberedButton = IconButton("list.number", hint: "Numbered List")
    private let agentButton = IconButton("desktopcomputer", hint: "")
    let clearButton = IconButton("xmark.circle.fill", hint: "Close Page", width: clearW)
    private lazy var sizeField = FontSizeField(value: fontSize, range: 10...24)
    let urlBox = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: toolH))
    let urlField = FadingField(frame: .zero)
    private let tray = NSView()
    private let hintView = NSView()
    private let hintLabel = NSTextField(labelWithString: "")

    private var hintTimer: Timer?
    private var saveTimer: Timer?
    private var hoverTimer: Timer?
    private var openTimer: Timer?
    private var frontTimer: Timer?
    private var hotKey: HotKey?

    // Formatting tools, left of the notch; they overflow into the tray from the last one
    private var formatTools: [NSView] { [checklistButton, numberedButton, sizeField] }

    var allWebViews: [WKWebView] { (webView.map { [$0] } ?? []) + popups }
    var shownWeb: WKWebView? { popups.last ?? webView }
    var shownAddress: String { popups.last.map { $0.url?.absoluteString ?? "" } ?? webURL }

    var panelSize: CGSize { CGSize(width: panelW, height: panelH) }

    // Padded by 1pt: CGRect.contains excludes the max edges, and the cursor sits
    // exactly on the top edge at the top of the screen, which made hover flicker
    private var isMouseInside: Bool {
        (isExpanded ? expandedFrame : collapsedFrame).insetBy(dx: -1, dy: -1).contains(NSEvent.mouseLocation)
    }

    // A sliver taller than the notch, for the line under it while a page plays sound
    private var collapsedFrame: CGRect {
        let s = notchScreen.frame, n = notchSize, w = n.width + 2 * collapsedRadius, h = n.height + soundH
        return CGRect(x: s.midX - w / 2, y: s.maxY - h, width: w, height: h)
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
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
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
        [scrollView, webHost, loadingPill, pager, quitButton, lockButton, captureButton, moreButton].forEach(panel.addSubview)
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
        // Sound line: beside the panel's own view, which is invisible while the panel is closed
        soundLine.wantsLayer = true
        cv.superview?.addSubview(soundLine, positioned: .below, relativeTo: cv)

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

        scheduleFrontCheck()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        hotKey = HotKey(keyCode: hotKeyCode, modifiers: hotKeyModifiers) { [weak self] in self?.toggleFromKeyboard() }

        // A panel that was locked open comes back open, without taking the keyboard from the app in front
        if isLocked { expand(focus: false) }
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
        // 2pt above the text and none below (see textContainerOrigin): the gap under the notes is the scroll view's
        textView.textContainerInset = CGSize(width: 10, height: 1)
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.setAccessibilityLabel("Notes")
        loadNote(notes.index(named: UserDefaults.standard.string(forKey: "currentNote") ?? "") ?? 0)
        textView.onChange = { [weak self] in self?.scheduleSave(); self?.updateListButtons() }
        textView.onOpenLink = { [weak self] in self?.openLink($0) }
        pager.onSelect = { [weak self] in self?.switchNote(to: $0) }
        pager.onAdd = { [weak self] in self?.newNote() }
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
        urlField.setAccessibilityLabel("Search or URL")
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

    func layoutControls() {
        // Content: notes or web page, below the notch
        let contentH = panelH - notchSize.height
        // The notes keep the same gap from the bottom edge as the text has from the sides
        let notesPad = textView.textContainerInset.width + (textView.textContainer?.lineFragmentPadding ?? 0)
        scrollView.frame = CGRect(x: 0, y: notesPad, width: panelW, height: contentH - notesPad)
        webHost.frame = CGRect(x: 0, y: 0, width: panelW, height: contentH).insetBy(dx: webInset, dy: webInset)
        clearButton.hint = popups.isEmpty ? "Close Page" : "Close Pop-up"
        textView.minSize = CGSize(width: 0, height: scrollView.contentSize.height)
        textView.frame.size.width = scrollView.contentSize.width
        clipWebView()

        // Note dots sit in the gap under the notes, between the resize grips
        let pagerW = min(pager.idealWidth, panelW - 80)
        pager.frame = CGRect(x: ((panelW - pagerW) / 2).rounded(), y: 0, width: pagerW, height: notesPad)
        pager.isHidden = webView != nil

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

    func closeTray() {
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
            if r / 2.squareRoot() > webInset + 1, visible.width > 2 * r, visible.height > 2 * r {
                let v = visible, d = webInset
                let curve = cornerCurve(radius: r, inset: d).map { CGPoint(x: v.minX - d + $0.x, y: v.minY - d + $0.y) }
                // The same curve on all four corners, mirrored across the page's centre lines
                let mx = v.minX + v.maxX, my = v.minY + v.maxY
                let path = CGMutablePath()
                path.addLines(between: curve
                    + curve.reversed().map { CGPoint(x: mx - $0.x, y: $0.y) }
                    + curve.map { CGPoint(x: mx - $0.x, y: my - $0.y) }
                    + curve.reversed().map { CGPoint(x: $0.x, y: my - $0.y) })
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

    // A short notice under the notch (downloads, switching notes)
    func flash(_ text: String) {
        hintTimer?.invalidate()
        showHint(text, under: CGRect(x: panelW / 2, y: panelH - notchSize.height + 2, width: 0, height: 0))
        hintTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.hintView.isHidden = true
        }
    }

    // Keyboard focus goes to the page (or its pop-up), else the notes
    func focusContent() {
        window?.makeFirstResponder(shownWeb ?? textView)
    }

    // MARK: - Keyboard

    // ⌘-shortcuts that aren't plain editing commands; false passes the key on
    func handleShortcut(_ key: String) -> Bool {
        switch key {
        case "l": focusURLField()
        case "n" where webView == nil: newNote()
        case "{" where webView == nil: stepNote(-1)
        case "}" where webView == nil: stepNote(1)
        default: return false
        }
        return true
    }

    func handleEscape() -> Bool {
        guard let win = window, isExpanded, let responder = win.firstResponder as? NSTextView,
              !responder.hasMarkedText() else { return false }   // Esc first cancels text still being composed
        if responder === textView {
            collapse(force: true)
        } else {
            urlField.reset(to: shownAddress)
            sizeField.cancel()
            closeTray()
            focusContent()
        }
        return true
    }

    private func focusURLField() {
        if urlBox.superview === tray {
            tray.isHidden = false
            moreButton.isActive = true
        }
        window?.makeFirstResponder(urlField)
    }

    // The global hotkey opens the panel wherever the mouse is, and closes it again
    func toggleFromKeyboard() {
        if isExpanded { return collapse(force: true) }
        keyboardOpened = true
        expand()
    }

    // MARK: - Notes

    private func loadNote(_ index: Int) {
        noteIndex = index
        do {
            textView.string = try notes.read(at: index)
            noteUnreadable = false
        } catch {
            textView.string = ""
            noteUnreadable = true
        }
        // A note that couldn't be read is left alone on disk: no editing, no saving
        textView.isEditable = !noteUnreadable
        textView.placeholder = noteUnreadable
            ? "Couldn't read \(notes.name(at: index)). Fix or move the file, then relaunch."
            : "Type your notes here..."
        textView.undoManager?.removeAllActions()
        textView.restyle()
        notesDirty = false
        UserDefaults.standard.set(notes.name(at: index), forKey: "currentNote")
        pager.set(count: notes.count, current: index)
        updateListButtons()
    }

    private func switchNote(to index: Int) {
        guard webView == nil, index != noteIndex, notes.files.indices.contains(index) else { return }
        saveNow()
        var target = index
        // Empty notes aren't kept
        if textView.string.isEmpty, !noteUnreadable, notes.count > 1 {
            notes.remove(at: noteIndex)
            if target > noteIndex { target -= 1 }
        }
        loadNote(target)
        layoutControls()   // the row of dots changed width
        flash("Note \(target + 1) of \(notes.count)")
        window?.makeFirstResponder(textView)
    }

    private func newNote() {
        // The note being shown is the new one if it's still empty
        guard webView == nil, noteUnreadable || !textView.string.isEmpty else { return }
        switchNote(to: notes.add())
    }

    // Next from the last note starts a new one
    private func stepNote(_ delta: Int) {
        let target = noteIndex + delta
        if target == notes.count { newNote() } else { switchNote(to: target) }
    }

    // ⌘-clicked link in the notes: shown in the panel like any other page
    private func openLink(_ url: URL) {
        urlField.reset(to: url.absoluteString)
        setWebURL(url.absoluteString)
        closeTray()
        focusContent()
    }

    // MARK: - Toggles, lists and font

    // The button shows the agent in use; the open page is reloaded so the site sees the new one
    func applyAgent(reload: Bool) {
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
        // Nothing to watch for while locked; unlocking goes back to closing when the mouse leaves
        if isLocked { hoverTimer?.invalidate() } else if isExpanded { startHoverPoll() }
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

    // The check is only urgent while the panel is showing; collapsed, it just has to be in front by the next hover
    private func scheduleFrontCheck() {
        frontTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: isExpanded ? 1 : 5, repeats: true) { [weak self] _ in self?.stayInFront() }
        t.tolerance = isExpanded ? 0.2 : 1
        frontTimer = t
    }

    // The screens were rearranged, or one was added or removed: go back to the notch, at a size that fits
    @objc private func screensChanged() {
        guard let win = window, !NSScreen.screens.isEmpty else { return }
        let size = clamped(panelSize)
        panelW = size.width
        panelH = size.height
        animationID += 1
        win.setFrame(isExpanded ? expandedFrame : collapsedFrame, display: true)
        layoutControls()
    }

    // Other apps' overlays (a screen-share border, say) also sit at the max level; re-order on top if anything there is in front of us
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

    // The mouse reached the notch: open if it is still there a moment later, so passing over on the way
    // to the menu bar doesn't open the panel
    func hoverBegan() {
        guard !isExpanded, openTimer == nil else { return }
        openTimer = Timer.scheduledTimer(withTimeInterval: hoverDelay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.openTimer = nil
            // The window's own frame, so coming back while it is still shrinking reopens it
            if let win = self.window, win.frame.insetBy(dx: -1, dy: -1).contains(NSEvent.mouseLocation) { self.expand() }
        }
    }

    // Collapse once the cursor is outside with no button held (so not mid-resize or mid-selection).
    // Polled rather than driven by mouse-exit events: a quick hover in and out can leave before the
    // growing window reaches the cursor, and then no exit event ever fires
    private func startHoverPoll() {
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, !NSScreen.screens.isEmpty, NSEvent.pressedMouseButtons == 0 else { return }
            let inside = self.isMouseInside
            if self.keyboardOpened {
                if inside { self.keyboardOpened = false }
                return
            }
            if !inside { self.collapse() }
        }
    }

    // Appear instantly at notch size, then expand
    func expand(focus: Bool = true) {
        guard !isExpanded, let win = window else { return }
        isExpanded = true
        animationID += 1
        let id = animationID
        stayInFront()
        scheduleFrontCheck()
        win.contentView?.alphaValue = 1
        updateSoundLine()
        if !isLocked { startHoverPoll() }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            win.animator().setFrame(expandedFrame, display: true)
        } completionHandler: { [weak self] in
            guard let self, self.animationID == id, focus else { return }
            win.makeKeyAndOrderFront(nil)
            self.focusContent()
        }
    }

    // Shrink back to the notch, then fade out. Esc and the hotkey close even a locked panel
    private func collapse(force: Bool = false) {
        guard isExpanded, force || !isLocked, let win = window, win.attachedSheet == nil else { return }
        hoverTimer?.invalidate()
        isExpanded = false
        keyboardOpened = false
        scheduleFrontCheck()
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
            self?.updateSoundLine()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                win.contentView?.animator().alphaValue = 0
            }
        }
    }

    // While the panel is closed, a page making sound shows as a thin line hugging the notch, with pulses running
    // up it. Run when the panel opens or has closed, and when the sound starts or stops
    func updateSoundLine() {
        let screen = notchScreen, on = !isExpanded && allWebViews.contains { $0.isPlayingSound }
        soundLine.isHidden = !on
        soundLine.layer?.mask = nil
        // The screen's own outline, notch included, moved into the window (not public: without it there is no line).
        // Stroked along that edge, the half of the line inside the notch simply isn't there
        guard on, let frame = window?.frame, screen.responds(to: NSSelectorFromString("bezelPath")),
              let outline = (screen.value(forKey: "bezelPath") as? NSBezierPath)?.copy() as? NSBezierPath else { return }
        outline.transform(using: AffineTransform(translationByX: screen.frame.minX - frame.minX, byY: screen.frame.minY - frame.minY))
        outline.lineWidth = 2 * soundH
        soundLine.frame.size = frame.size
        soundLine.image = NSImage(size: frame.size, flipped: false) { _ in NSColor.controlAccentColor.set(); outline.stroke(); return true }

        // The pulse is a mask: the line shows faintly, and fully where a ring passes that keeps growing out of the
        // middle of the notch's lower edge. A square stood on its corner, so it moves along the line at an even pace
        let mask = CALayer(), ring = CALayer(), pulse = CABasicAnimation(keyPath: "bounds")
        mask.frame.size = frame.size
        mask.backgroundColor = NSColor(white: 0, alpha: 0.3).cgColor
        mask.addSublayer(ring)
        ring.position.x = frame.width / 2
        ring.borderWidth = 20
        ring.setAffineTransform(CGAffineTransform(rotationAngle: .pi / 4))
        pulse.toValue = CGRect(x: 0, y: 0, width: 300, height: 300)
        pulse.duration = 2
        pulse.repeatCount = .infinity
        ring.add(pulse, forKey: nil)
        soundLine.layer?.mask = mask
    }

    // MARK: - Saving

    private func scheduleSave() {
        notesDirty = true
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in self?.saveNow() }
    }

    // Only what was typed here is written, so a file changed elsewhere isn't overwritten by an untouched copy
    func saveNow() {
        saveTimer?.invalidate()
        guard notesDirty, !noteUnreadable else { return }
        do {
            try notes.write(textView.string, at: noteIndex)
            notesDirty = false
            saveFailed = false
        } catch {
            if !saveFailed { flash("Couldn't save \(notes.name(at: noteIndex))") }
            saveFailed = true
        }
    }
}
