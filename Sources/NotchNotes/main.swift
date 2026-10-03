import Cocoa
import WebKit

// MARK: - Persistence

let notesURL: URL = {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NotchNotes")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("notes.txt")
}()

func stored(_ key: String, default value: CGFloat) -> CGFloat {
    let v = UserDefaults.standard.double(forKey: key)
    return v > 0 ? CGFloat(v) : value
}

func store(_ value: CGFloat, _ key: String) {
    UserDefaults.standard.set(Double(value), forKey: key)
}

// MARK: - Notch geometry

var notchScreen: NSScreen {
    NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
}

var notchSize: CGSize {
    let s = notchScreen
    if s.safeAreaInsets.top > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
        return CGSize(width: s.frame.width - l.width - r.width, height: s.safeAreaInsets.top)
    }
    return CGSize(width: 185, height: 32)
}

// MARK: - Constants

let expandedRadius:  CGFloat = 16
let collapsedRadius: CGFloat = 8
let animDuration:    TimeInterval = 0.22
let edgeInset: CGFloat = 12                 // quit / eye distance from the side edges
let quitW:     CGFloat = 14
let toggleW:   CGFloat = 30
let toolW:     CGFloat = 24
let toolH:     CGFloat = 20
let toolGap:   CGFloat = 2
let groupGap:  CGFloat = 10
let notchGap:  CGFloat = 8
let urlMinW:   CGFloat = 80                 // URL field shrinks with the space beside the notch
let urlMaxW:   CGFloat = 180
let urlTrayW:  CGFloat = 120                // URL field width inside the "…" tray
let clearW:    CGFloat = 16                 // clear button inside the URL field
let leftTools  = 4                          // tools left of the notch; the rest go right
let webInset:  CGFloat = 6                  // black border around web pages
let topLevel = Int(CGWindowLevelForKey(.maximumWindow))   // same level as Teams' share border

// Corner radius of the notch shape at a given window height (grows as it expands)
func shapeRadius(height h: CGFloat, fullHeight: CGFloat) -> CGFloat {
    let nh = notchSize.height
    let t = max(0, min(1, (h - nh) / max(fullHeight - nh, 1)))
    return collapsedRadius + (expandedRadius - collapsedRadius) * t
}

// MARK: - Window

class NotchWindow: NSPanel {
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
        ]
        guard let action = actions[key] else { return super.performKeyEquivalent(with: event) }
        return NSApp.sendAction(action, to: nil, from: self)
    }
}

// MARK: - Icon button (quit, eye, tools, "…")

final class IconButton: NSView {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var hint: () -> String
    var isActive = false { didSet { refresh() } }
    var iconColor = NSColor(white: 0.7, alpha: 1) { didSet { refresh() } }
    var fill = NSColor.clear { didSet { refresh() } }
    var hoverFill = NSColor(white: 1, alpha: 0.12) { didSet { refresh() } }

    private let icon = NSImageView()
    private var hovering = false { didSet { refresh() } }

    init(_ symbol: String, hint: String, width: CGFloat = toolW) {
        self.hint = { hint }
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: toolH))
        wantsLayer = true
        layer?.cornerRadius = 6
        icon.frame = bounds
        icon.autoresizingMask = [.width, .height]
        icon.imageScaling = .scaleNone
        addSubview(icon)
        setSymbol(symbol)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSymbol(_ name: String) {
        icon.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        refresh()
    }

    private func refresh() {
        icon.contentTintColor = iconColor
        layer?.backgroundColor = (hovering || isActive ? hoverFill : fill).cgColor
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; onHover?(true) }
    override func mouseExited(with event: NSEvent) { hovering = false; onHover?(false) }
    override func mouseDown(with event: NSEvent) { onHover?(false); onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Fading text field (overflowing text fades out at whichever edge is clipped)

// Vertically centres the text and uses the same rect for drawing and editing,
// so the text doesn't jump when the field editor takes over on click
final class CenteredCell: NSTextFieldCell {
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        let h = cellSize(forBounds: rect).height
        return NSRect(x: rect.minX, y: rect.minY + (rect.height - h) / 2, width: rect.width, height: h)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: titleRect(forBounds: cellFrame), in: controlView)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                       delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: titleRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                         delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: titleRect(forBounds: rect), in: controlView, editor: textObj,
                     delegate: delegate, start: selStart, length: selLength)
    }
}

final class FadingField: NSTextField {
    private let fade = CAGradientLayer()
    private let fadeW: CGFloat = 10

    override init(frame: NSRect) {
        super.init(frame: frame)
        let c = CenteredCell(textCell: "")
        c.isEditable = true
        c.isScrollable = true
        c.wraps = false
        c.usesSingleLineMode = true
        c.lineBreakMode = .byClipping
        cell = c

        wantsLayer = true
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.mask = fade
        NotificationCenter.default.addObserver(self, selector: #selector(editorChanged(_:)),
                                               name: NSTextView.didChangeSelectionNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateFades() {
        let left: Bool, right: Bool
        if let editor = currentEditor() as? NSTextView {
            let v = editor.visibleRect
            left = v.minX > 1
            right = v.maxX < editor.bounds.width - 1
        } else {
            left = false
            right = attributedStringValue.size().width > bounds.width - 4
        }
        let clear = NSColor.clear.cgColor, solid = NSColor.black.cgColor
        let f = NSNumber(value: Double(fadeW / max(bounds.width, 1)))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = bounds
        fade.colors = [left ? clear : solid, solid, solid, right ? clear : solid]
        fade.locations = [0, f, NSNumber(value: 1 - f.doubleValue), 1]
        CATransaction.commit()
    }

    // The field editor scrolls after these events, so update on the next run loop pass
    private func updateFadesSoon() { DispatchQueue.main.async { [weak self] in self?.updateFades() } }

    @objc private func editorChanged(_ note: Notification) {
        if note.object as AnyObject === currentEditor() { updateFadesSoon() }
    }

    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); updateFades() }
    override func textDidChange(_ notification: Notification) { super.textDidChange(notification); updateFadesSoon() }
    override func textDidEndEditing(_ notification: Notification) { super.textDidEndEditing(notification); updateFadesSoon() }
}

// MARK: - Resize grip (bottom corners)

final class ResizeHandle: NSView {
    weak var wc: NotchWindowController?
    private let isRight: Bool
    private var startMouse = NSPoint.zero
    private var startSize = CGSize.zero
    private var hovering = false { didSet { needsDisplay = true } }
    private var dragging = false { didSet { needsDisplay = true; window?.invalidateCursorRects(for: self) } }

    init(right: Bool) {
        isRight = right
        super.init(frame: CGRect(x: 0, y: 0, width: 28, height: 28))
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError() }

    // Mac-style curved grabber hugging the corner, shown on hover / drag
    override func draw(_ dirtyRect: NSRect) {
        guard hovering || dragging else { return }
        let r = expandedRadius - 5, tail: CGFloat = 2, cy = expandedRadius
        let s: CGFloat = isRight ? 1 : -1
        let cx = isRight ? bounds.width - expandedRadius : expandedRadius

        let path = NSBezierPath()
        path.move(to: NSPoint(x: cx - s * tail, y: cy - r))
        path.line(to: NSPoint(x: cx, y: cy - r))
        path.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: r,
                       startAngle: 270, endAngle: isRight ? 360 : 180, clockwise: !isRight)
        path.line(to: NSPoint(x: cx + s * r, y: cy + tail))
        path.lineWidth = 2.5
        path.lineCapStyle = .round
        NSColor(white: 1, alpha: dragging ? 0.75 : 0.5).setStroke()
        path.stroke()
    }

    private var cursor: NSCursor { dragging ? .closedHand : .openHand }

    override func resetCursorRects() { addCursorRect(bounds, cursor: cursor) }
    override func cursorUpdate(with event: NSEvent) { cursor.set() }
    override func mouseMoved(with event: NSEvent) { cursor.set() }
    override func mouseEntered(with event: NSEvent) { hovering = true; cursor.set() }
    override func mouseExited(with event: NSEvent) { hovering = false; if !dragging { NSCursor.arrow.set() } }

    override func mouseDown(with event: NSEvent) {
        dragging = true
        cursor.set()
        startMouse = NSEvent.mouseLocation
        startSize = wc?.panelSize ?? .zero
        wc?.isResizing = true
    }

    override func mouseDragged(with event: NSEvent) {
        cursor.set()
        let p = NSEvent.mouseLocation
        // Width grows on both sides so the panel stays centered on the notch
        wc?.resizePanel(to: CGSize(width: startSize.width + (p.x - startMouse.x) * (isRight ? 2 : -2),
                                   height: startSize.height + startMouse.y - p.y))
    }

    override func mouseUp(with event: NSEvent) {
        dragging = false
        hovering = bounds.contains(convert(event.locationInWindow, from: nil))
        (hovering ? NSCursor.openHand : .arrow).set()
        wc?.endResize()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Text view (placeholder, checkboxes, lists)

final class NoteTextView: NSTextView {
    var onChange: (() -> Void)?
    private var boxes: [(range: NSRange, checked: Bool)] = []

    // "- [ ] item" / "- [x] item": group 1 = "- [ ]", 2 = mark, 3 = text
    static let checkboxRegex = try! NSRegularExpression(pattern: "^[ \\t]*(- \\[([ xX])\\])(.*)$",
                                                        options: .anchorsMatchLines)

    private var baseAttrs: [NSAttributedString.Key: Any] {
        [.font: font ?? .monospacedSystemFont(ofSize: 13, weight: .regular),
         .foregroundColor: NSColor(white: 0.92, alpha: 1)]
    }

    // Hide "- [ ]" (a checkbox is drawn over it) and dim checked items
    func restyle() {
        guard let ts = textStorage else { return }
        let full = NSRange(location: 0, length: ts.length)
        boxes = []
        ts.beginEditing()
        ts.setAttributes(baseAttrs, range: full)
        Self.checkboxRegex.enumerateMatches(in: ts.string, range: full) { m, _, _ in
            guard let m else { return }
            let checked = (ts.string as NSString).substring(with: m.range(at: 2)) != " "
            boxes.append((m.range(at: 1), checked))
            ts.addAttribute(.foregroundColor, value: NSColor.clear, range: m.range(at: 1))
            if checked {
                ts.addAttributes([.foregroundColor: NSColor(white: 0.45, alpha: 1),
                                  .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: m.range(at: 3))
            }
        }
        ts.endEditing()
        typingAttributes = baseAttrs
        needsDisplay = true
    }

    // Toggle "- [ ] " or "- " on the current / selected lines
    func toggleList(checkbox: Bool) {
        struct Line { var indent: String; var prefix: String; var body: String }

        let range = (string as NSString).lineRange(for: selectedRange())
        let block = (string as NSString).substring(with: range)
        let trailingNewline = block.hasSuffix("\n")
        var raw = block.components(separatedBy: "\n")
        if trailingNewline { raw.removeLast() }

        let lines: [Line] = raw.map { line in
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            let rest = String(line.dropFirst(indent.count))
            for p in ["- [ ] ", "- [x] ", "- [X] ", "- "] where rest.hasPrefix(p) {
                return Line(indent: indent, prefix: p, body: String(rest.dropFirst(p.count)))
            }
            return Line(indent: indent, prefix: "", body: rest)
        }

        let isTarget: (Line) -> Bool = { checkbox ? $0.prefix.count == 6 : $0.prefix == "- " }
        let content = lines.filter { !($0.prefix + $0.body).trimmingCharacters(in: .whitespaces).isEmpty }
        let removing = !content.isEmpty && content.allSatisfy(isTarget)

        var replacement = lines.map { l -> String in
            let blank = l.prefix.isEmpty && l.body.trimmingCharacters(in: .whitespaces).isEmpty
            if removing || (blank && lines.count > 1) { return l.indent + l.body }
            return l.indent + (checkbox ? "- [ ] " : "- ") + l.body
        }.joined(separator: "\n")
        if trailingNewline { replacement += "\n" }

        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        let end = range.location + (replacement as NSString).length - (trailingNewline ? 1 : 0)
        setSelectedRange(NSRange(location: end, length: 0))
    }

    private func boxRect(for range: NSRange) -> CGRect {
        guard let lm = layoutManager, let tc = textContainer else { return .zero }
        let r = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: tc)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        let s = font?.pointSize ?? 13
        return CGRect(x: r.minX + (r.width - s) / 2, y: r.midY - s / 2, width: s, height: s)
    }

    override func didChangeText() {
        restyle()
        super.didChangeText()
        onChange?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for box in boxes {
            let rect = boxRect(for: box.range)
            guard rect.intersects(dirtyRect) else { continue }
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            if box.checked {
                NSColor.controlAccentColor.setFill()
                path.fill()
                let check = NSBezierPath()
                check.move(to: NSPoint(x: rect.minX + rect.width * 0.23, y: rect.midY))
                check.line(to: NSPoint(x: rect.minX + rect.width * 0.42, y: rect.maxY - rect.height * 0.27))
                check.line(to: NSPoint(x: rect.maxX - rect.width * 0.23, y: rect.minY + rect.height * 0.27))
                check.lineWidth = 1.6
                check.lineCapStyle = .round
                NSColor.white.setStroke()
                check.stroke()
            } else {
                path.lineWidth = 1.2
                NSColor(white: 0.55, alpha: 1).setStroke()
                path.stroke()
            }
        }

        if string.isEmpty {
            let x = textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0)
            "Type your notes here...".draw(at: NSPoint(x: x, y: textContainerInset.height), withAttributes: [
                .foregroundColor: NSColor(white: 0.5, alpha: 1),
                .font: font ?? .monospacedSystemFont(ofSize: 13, weight: .regular),
            ])
        }
    }

    // Click a checkbox to toggle it
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let box = boxes.first(where: { boxRect(for: $0.range).insetBy(dx: -4, dy: -4).contains(p) }) {
            let mark = NSRange(location: box.range.location + 3, length: 1)
            let replacement = box.checked ? " " : "x"
            if shouldChangeText(in: mark, replacementString: replacement) {
                textStorage?.replaceCharacters(in: mark, with: replacement)
                didChangeText()
            }
            return
        }
        super.mouseDown(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Enter on a checkbox line continues the list; Enter on an empty item ends it
    override func insertNewline(_ sender: Any?) {
        let sel = selectedRange()
        let lineRange = (string as NSString).lineRange(for: NSRange(location: sel.location, length: 0))
        let line = (string as NSString).substring(with: lineRange).trimmingCharacters(in: .newlines) as NSString
        guard let m = Self.checkboxRegex.firstMatch(in: line as String, range: NSRange(location: 0, length: line.length)) else {
            return super.insertNewline(sender)
        }
        let indent = line.substring(to: m.range(at: 1).location)
        if line.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespaces).isEmpty {
            insertText(indent, replacementRange: NSRange(location: lineRange.location, length: line.length))
        } else {
            insertText("\n" + indent + "- [ ] ", replacementRange: sel)
        }
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

    override func mouseEntered(with event: NSEvent) { wc?.expand() }

    override func mouseExited(with event: NSEvent) {
        guard let wc, !wc.isResizing, !wc.isMouseInside else { return }
        wc.collapse()
    }
}

// MARK: - Window controller

final class NotchWindowController: NSWindowController {
    private(set) var isExpanded = false
    var isResizing = false
    private(set) var panelW = stored("panelW", default: 500)
    private(set) var panelH = stored("panelH", default: 280)
    private var fontSize = stored("fontSize", default: 13)
    private var webURL = UserDefaults.standard.string(forKey: "webURL") ?? ""
    private var hiddenFromCapture = true
    private var animationID = 0   // ignores completions from interrupted animations

    private var panel: NSView!
    private var scrollView: NSScrollView!
    private var textView: NoteTextView!
    private var webView: WKWebView?
    private let webMask = CAShapeLayer()
    private var themeObservation: NSKeyValueObservation?
    private var urlBox: NSView!
    private var urlField: FadingField!
    private var clearButton: IconButton!
    private var quitButton: IconButton!
    private var captureButton: IconButton!
    private var moreButton: IconButton!
    private var tools: [NSView] = []
    private var tray: NSView!
    private var hintView: NSView!
    private var hintLabel: NSTextField!
    private var hintTimer: Timer?
    private var saveTimer: Timer?
    private var levelTimer: Timer?

    var panelSize: CGSize { CGSize(width: panelW, height: panelH) }
    var panelTotalW: CGFloat { panelW + 2 * expandedRadius }

    // Padded by 1pt: CGRect.contains excludes the max edges, and the cursor sits
    // exactly on the top edge at the top of the screen, which made hover flicker
    var isMouseInside: Bool {
        (isExpanded ? expandedFrame : collapsedFrame).insetBy(dx: -1, dy: -1).contains(NSEvent.mouseLocation)
    }

    private var collapsedFrame: CGRect {
        let s = notchScreen.frame, n = notchSize, w = n.width + 2 * collapsedRadius
        return CGRect(x: s.midX - w / 2, y: s.maxY - n.height, width: w, height: n.height)
    }

    private var expandedFrame: CGRect {
        let s = notchScreen.frame
        return CGRect(x: s.midX - panelTotalW / 2, y: s.maxY - panelH, width: panelTotalW, height: panelH)
    }

    private func rowWidth<C: Collection>(_ views: C) -> CGFloat where C.Element == NSView {
        views.reduce(0) { $0 + $1.frame.width } + CGFloat(max(views.count - 1, 0)) * toolGap
    }

    // Minimum space each side needs in overflow mode (eye + "…")
    private var compactSide: CGFloat { edgeInset + toggleW + 6 + toolW + notchGap }

    private func clamped(_ size: CGSize) -> CGSize {
        let s = notchScreen.frame, n = notchSize
        return CGSize(width: min(max(size.width, n.width + 2 * compactSide), s.width - 2 * expandedRadius - 40).rounded(),
                      height: min(max(size.height, n.height + 80), s.height * 0.9).rounded())
    }

    convenience init() {
        let win = NotchWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.sharingType = .none
        win.level = NSWindow.Level(rawValue: topLevel)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.ignoresMouseEvents = false   // keep receiving hover while fully transparent
        win.hasShadow = false
        win.hidesOnDeactivate = false
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.init(window: win)
    }

    func buildUI() {
        guard let win = window else { return }
        let size = clamped(panelSize)
        panelW = size.width
        panelH = size.height
        win.setFrame(expandedFrame, display: false)

        let cv = NotchContentView(frame: CGRect(origin: .zero, size: expandedFrame.size))
        cv.wc = self
        win.contentView = cv

        // Notes (text area sits below the notch so nothing hides behind the camera)
        let sv = NSScrollView()
        sv.hasVerticalScroller = true
        sv.backgroundColor = .black
        scrollView = sv

        let tv = NoteTextView()
        tv.autoresizingMask = [.width]
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        tv.backgroundColor = .black
        tv.insertionPointColor = NSColor(white: 0.7, alpha: 1)
        tv.selectedTextAttributes = [.backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.5),
                                     .foregroundColor: NSColor.white]
        tv.textContainerInset = CGSize(width: 10, height: 10)
        tv.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.string = (try? String(contentsOf: notesURL, encoding: .utf8)) ?? ""
        tv.restyle()
        tv.onChange = { [weak self] in self?.scheduleSave() }
        sv.documentView = tv
        textView = tv

        // Top strip buttons
        quitButton = IconButton("circle.fill", hint: "Quit NotchNotes", width: quitW)
        quitButton.iconColor = NSColor(red: 1, green: 0.37, blue: 0.37, alpha: 1)
        quitButton.hoverFill = .clear
        quitButton.onClick = { NSApp.terminate(nil) }

        captureButton = IconButton("eye.slash.fill", hint: "", width: toggleW)
        captureButton.layer?.cornerRadius = toolH / 2
        captureButton.hint = { [weak self] in
            self?.hiddenFromCapture == true ? "Hidden from screen recording (click to show)"
                                            : "Visible in screen recording (click to hide)"
        }
        captureButton.onClick = { [weak self] in self?.toggleCapture() }
        updateCaptureButton()

        // URL field: Return loads the page, empty + Return goes back to notes
        urlBox = NSView(frame: CGRect(x: 0, y: 0, width: urlMinW, height: toolH))
        urlBox.wantsLayer = true
        urlBox.layer?.cornerRadius = 6

        urlField = FadingField(frame: urlBox.bounds.insetBy(dx: 6, dy: 0))
        urlField.autoresizingMask = [.width, .height]
        urlField.placeholderString = "Paste URL"
        urlField.font = .systemFont(ofSize: 11)
        urlField.textColor = NSColor(white: 0.92, alpha: 1)
        urlField.isBezeled = false
        urlField.drawsBackground = false
        urlField.focusRingType = .none
        urlField.target = self
        urlField.action = #selector(urlEntered)
        urlBox.addSubview(urlField)

        // Clear button at the right end of the URL field, shown while a page is loaded
        clearButton = IconButton("xmark.circle.fill", hint: "Back to notes", width: clearW)
        clearButton.frame.origin.x = urlBox.bounds.width - clearW - 2
        clearButton.autoresizingMask = [.minXMargin]
        clearButton.hoverFill = .clear
        clearButton.onClick = { [weak self] in
            guard let self else { return }
            if self.urlField.currentEditor() != nil { self.urlField.abortEditing() }
            self.setWebURL("")
            self.window?.makeFirstResponder(self.textView)
        }
        urlBox.addSubview(clearButton)

        let toolSpecs: [(String, String, (NotchWindowController) -> Void)] = [
            ("checklist",               "Checklist",    { $0.textView.toggleList(checkbox: true) }),
            ("list.bullet",             "Bullet list",  { $0.textView.toggleList(checkbox: false) }),
            ("textformat.size.smaller", "Smaller text", { $0.changeFontSize(by: -1) }),
            ("textformat.size.larger",  "Larger text",  { $0.changeFontSize(by: 1) }),
        ]
        let iconTools = toolSpecs.map { symbol, hint, action in
            let b = IconButton(symbol, hint: hint)
            b.onClick = { [weak self] in if let self { action(self) } }
            return b
        }
        tools = iconTools + [urlBox]

        moreButton = IconButton("ellipsis", hint: "Formatting")
        moreButton.onClick = { [weak self] in self?.toggleTray() }

        for b in [quitButton!, captureButton!, moreButton!, clearButton!] + iconTools {
            b.onHover = { [weak self, weak b] on in
                if let self, let b { self.hover(b, on) }
            }
        }

        // Overflow tray for tools when the panel is narrow
        tray = NSView()
        tray.wantsLayer = true
        tray.layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
        tray.layer?.cornerRadius = 8
        tray.isHidden = true

        // In-panel hint (system tooltips use their own window and leak into screen shares)
        hintLabel = NSTextField(labelWithString: "")
        hintLabel.font = .systemFont(ofSize: 11, weight: .medium)
        hintLabel.textColor = NSColor(white: 0.92, alpha: 1)
        hintView = NSView()
        hintView.wantsLayer = true
        hintView.layer?.backgroundColor = NSColor(white: 0.18, alpha: 1).cgColor
        hintView.layer?.cornerRadius = 5
        hintView.addSubview(hintLabel)
        hintView.isHidden = true

        let leftGrip = ResizeHandle(right: false)
        let rightGrip = ResizeHandle(right: true)
        rightGrip.frame.origin.x = panelW - rightGrip.frame.width
        rightGrip.autoresizingMask = [.minXMargin]
        leftGrip.wc = self
        rightGrip.wc = self

        panel = NSView(frame: CGRect(x: 0, y: 0, width: panelW, height: panelH))
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor.black.cgColor
        let views: [NSView] = [sv, quitButton, captureButton, moreButton, leftGrip, rightGrip, tray, hintView]
        views.forEach(panel.addSubview)
        cv.addSubview(panel)
        cv.panel = panel
        layoutControls()
        setWebURL(webURL)

        // The panel is forced dark, but web pages follow the system light/dark setting
        themeObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.applySystemTheme() }
        }

        // Start collapsed and fully transparent
        win.setFrame(collapsedFrame, display: false)
        cv.alphaValue = 0

        levelTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.stayInFront() }
    }

    // MARK: - Layout

    private func layoutControls() {
        // Content: notes or web page, below the notch
        let contentH = panelH - notchSize.height
        scrollView.frame = CGRect(x: 0, y: 0, width: panelW, height: contentH)
        webView?.frame = scrollView.frame.insetBy(dx: webInset, dy: webInset)
        textView.minSize = CGSize(width: 0, height: scrollView.contentSize.height)
        textView.frame.size.width = scrollView.contentSize.width
        clipWebView()

        // Top strip: tools sit beside the notch when there's room, otherwise in the "…" tray
        let y = panelH - notchSize.height / 2 - toolH / 2
        quitButton.frame.origin = CGPoint(x: edgeInset, y: y)
        captureButton.frame.origin = CGPoint(x: panelW - edgeInset - toggleW, y: y)

        // Re-parent only when needed, so a field being edited isn't interrupted
        func place(_ v: NSView, in parent: NSView, x: CGFloat, y: CGFloat) {
            if v.superview !== parent { parent.addSubview(v, positioned: .below, relativeTo: parent === panel ? tray : nil) }
            v.frame.origin = CGPoint(x: x, y: y)
        }

        // Each side of the notch has the same space; the URL field takes what's left on the right
        // The formatting tools only apply to notes, so they're hidden while a web page is shown
        let web = webView != nil
        tools.prefix(leftTools).forEach { $0.isHidden = web }
        let left = web ? [] : Array(tools.prefix(leftTools)), right = Array(tools.dropFirst(leftTools))

        let side = (panelW - notchSize.width) / 2
        let leftNeeded = edgeInset + quitW + groupGap + rowWidth(left) + notchGap
        let urlRoom = side - (edgeInset + toggleW + groupGap + notchGap)
        let inline = side >= leftNeeded && urlRoom >= urlMinW
        moreButton.isHidden = inline
        urlBox.frame.size.width = inline ? min(urlRoom, urlMaxW).rounded(.down) : urlTrayW

        if inline {
            tray.isHidden = true
            moreButton.isActive = false
            var x = edgeInset + quitW + groupGap
            for v in left {
                place(v, in: panel, x: x, y: y)
                x += v.frame.width + toolGap
            }
            x = panelW - edgeInset - toggleW - groupGap - rowWidth(right)
            for v in right {
                place(v, in: panel, x: x, y: y)
                x += v.frame.width + toolGap
            }
        } else {
            moreButton.frame.origin = CGPoint(x: panelW - edgeInset - toggleW - 6 - toolW, y: y)
            let w = rowWidth(left + right) + 8, h = toolH + 8
            tray.frame = CGRect(x: moreButton.frame.maxX - w, y: y - 6 - h, width: w, height: h)
            var x: CGFloat = 4
            for v in left + right {
                place(v, in: tray, x: x, y: 4)
                x += v.frame.width + toolGap
            }
        }
    }

    // Clip the web page to the visible part of the notch shape, inset by the border,
    // so the black border follows the shape while it expands and collapses
    func clipWebView() {
        guard let wv = webView, let layer = wv.layer, let size = window?.contentView?.bounds.size else { return }
        let r = shapeRadius(height: size.height, fullHeight: panelH)

        // Visible body of the notch shape (excluding the flared top corners), in panel coordinates
        let originX = (size.width - panelW) / 2, originY = size.height - panelH
        let body = CGRect(x: r - originX, y: -originY, width: size.width - 2 * r, height: size.height)
            .insetBy(dx: webInset, dy: webInset)
        let visible = body.intersection(wv.frame)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        webMask.frame = layer.bounds
        if visible.isNull || visible.isEmpty {
            webMask.path = CGPath(rect: .zero, transform: nil)
        } else {
            let rect = wv.convert(visible, from: panel)
            let cr = min(max(r - webInset, 0), rect.width / 2, rect.height / 2)
            webMask.path = CGPath(roundedRect: rect, cornerWidth: cr, cornerHeight: cr, transform: nil)
        }
        layer.mask = webMask
        CATransaction.commit()
    }

    private func hover(_ b: IconButton, _ on: Bool) {
        hintTimer?.invalidate()
        hintView.isHidden = true
        guard on else { return }
        hintTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self, weak b] _ in
            guard let self, let b, b.window != nil else { return }
            self.hintLabel.stringValue = b.hint()
            let ls = self.hintLabel.fittingSize
            let w = ls.width + 12, h = ls.height + 6
            let a = b.convert(b.bounds, to: self.panel)
            self.hintView.frame = CGRect(x: min(max(a.midX - w / 2, 6), self.panelW - w - 6),
                                         y: a.minY - 6 - h, width: w, height: h)
            self.hintLabel.frame = CGRect(x: 6, y: 3, width: ls.width, height: ls.height)
            self.hintView.isHidden = false
        }
    }

    private func toggleTray() {
        tray.isHidden.toggle()
        moreButton.isActive = !tray.isHidden
    }

    // MARK: - Web page

    @objc private func urlEntered() {
        setWebURL(urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        window?.makeFirstResponder(webView ?? textView)
    }

    // Non-empty URL shows the web page; empty returns to the notes
    private func setWebURL(_ text: String) {
        let url = URL(string: text.contains("://") ? text : "https://" + text)
        if text.isEmpty || url == nil {
            webView?.removeFromSuperview()
            webView = nil
            webURL = ""
            scrollView.isHidden = false
        } else if let url {
            if webView == nil {
                let wv = WKWebView()
                wv.underPageBackgroundColor = .black
                wv.wantsLayer = true
                panel.addSubview(wv, positioned: .above, relativeTo: scrollView)
                webView = wv
                applySystemTheme()
            }
            webView?.load(URLRequest(url: url))
            webURL = text
            scrollView.isHidden = true
        }
        UserDefaults.standard.set(webURL, forKey: "webURL")
        urlField.stringValue = webURL
        urlField.updateFades()
        urlBox.layer?.backgroundColor = NSColor(white: 1, alpha: webView == nil ? 0.08 : 0.16).cgColor
        clearButton.isHidden = webView == nil
        urlField.frame.size.width = urlBox.bounds.width - 12 - (webView == nil ? 0 : clearW)
        layoutControls()
    }

    // Web pages see the system's light/dark setting via prefers-color-scheme
    private func applySystemTheme() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        webView?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }

    // MARK: - Capture visibility & font

    private func toggleCapture() {
        hiddenFromCapture.toggle()
        window?.sharingType = hiddenFromCapture ? NSWindow.SharingType.none : .readOnly
        updateCaptureButton()
    }

    private func updateCaptureButton() {
        let hidden = hiddenFromCapture
        let color: NSColor = hidden ? .white : .systemOrange
        captureButton.setSymbol(hidden ? "eye.slash.fill" : "eye.fill")
        captureButton.iconColor = hidden ? NSColor(white: 0.6, alpha: 1) : .systemOrange
        captureButton.fill = color.withAlphaComponent(hidden ? 0.08 : 0.2)
        captureButton.hoverFill = color.withAlphaComponent(hidden ? 0.16 : 0.3)
    }

    private func changeFontSize(by delta: CGFloat) {
        fontSize = min(max(fontSize + delta, 10), 24)
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.restyle()
        store(fontSize, "fontSize")
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

    func endResize() {
        isResizing = false
        store(panelW, "panelW")
        store(panelH, "panelH")
        if !isMouseInside { collapse() }
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

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            win.animator().setFrame(expandedFrame, display: true)
        } completionHandler: { [weak self] in
            guard let self, self.animationID == id else { return }
            win.makeKeyAndOrderFront(nil)
            win.makeFirstResponder(self.webView ?? self.textView)
        }
    }

    // Shrink back to the notch, then fade out
    func collapse() {
        guard isExpanded, let win = window else { return }
        isExpanded = false
        animationID += 1
        let id = animationID
        hintView.isHidden = true
        tray.isHidden = true
        moreButton.isActive = false
        if urlField.currentEditor() != nil { urlField.abortEditing() }   // drop unsubmitted edits
        urlField.stringValue = webURL
        urlField.updateFades()
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

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var wc: NotchWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        wc = NotchWindowController()
        wc.buildUI()
        wc.window?.orderFrontRegardless()
    }

    func applicationWillTerminate(_ notification: Notification) {
        wc.saveNow()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()