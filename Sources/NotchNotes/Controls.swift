import Cocoa

// MARK: - Icon button (quit, lock, eye, tools, "…")

final class IconButton: NSView {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var hint: String
    var symbol: String { didSet { refresh() } }
    var hoverSymbol: String? { didSet { refresh() } }   // shown instead of the symbol while hovered
    var isActive = false { didSet { refresh() } }
    var tint: NSColor? { didSet { refresh() } }         // active colour; nil = neutral white
    var iconColor = NSColor(white: 0.7, alpha: 1) { didSet { refresh() } }
    var hoverFill = NSColor(white: 1, alpha: 0.12) { didSet { refresh() } }

    private let icon = NSImageView()
    private var hovering = false { didSet { refresh() } }

    init(_ symbol: String, hint: String, width: CGFloat = toolW) {
        self.symbol = symbol
        self.hint = hint
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: toolH))
        wantsLayer = true
        layer?.cornerRadius = 6
        icon.frame = bounds
        icon.autoresizingMask = [.width, .height]
        icon.imageScaling = .scaleNone
        addSubview(icon)
        refresh()
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError() }

    private func refresh() {
        icon.image = NSImage(systemSymbolName: hovering ? hoverSymbol ?? symbol : symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        // Active: tinted icon on a soft wash of the same colour, like system toggles
        icon.contentTintColor = isActive ? (tint ?? .white) : iconColor
        let activeFill = tint?.withAlphaComponent(hovering ? 0.34 : 0.24) ?? hoverFill
        layer?.backgroundColor = (isActive ? activeFill : hovering ? hoverFill : .clear).cgColor
    }

    // Hit the button, not its image view: only the button accepts the first click on an unfocused panel
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }

    override func mouseEntered(with event: NSEvent) { hovering = true; onHover?(true) }
    override func mouseExited(with event: NSEvent) { hovering = false; onHover?(false) }
    override func mouseDown(with event: NSEvent) { onHover?(false); onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // VoiceOver: a button named by its hint, which already says what a press will do
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { hint }
    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}

// MARK: - Note dots (one per note under the notes, then a + for a new one)

final class NotePager: NSView {
    var onSelect: ((Int) -> Void)?
    var onAdd: (() -> Void)?
    private var count = 1
    private var current = 0

    // One slot per dot and one for the +; the slots narrow if the panel can't fit them all
    var idealWidth: CGFloat { CGFloat(count + 1) * 14 }
    private var slot: CGFloat { bounds.width / CGFloat(count + 1) }

    func set(count: Int, current: Int) {
        self.count = max(count, 1)
        self.current = current
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let y = bounds.midY
        for i in 0..<count {
            let x = slot * (CGFloat(i) + 0.5), r: CGFloat = i == current ? 2.5 : 2
            NSColor(white: 1, alpha: i == current ? 0.85 : 0.3).setFill()
            NSBezierPath(ovalIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)).fill()
        }
        let x = slot * (CGFloat(count) + 0.5), arm: CGFloat = 3
        let plus = NSBezierPath()
        plus.move(to: NSPoint(x: x - arm, y: y))
        plus.line(to: NSPoint(x: x + arm, y: y))
        plus.move(to: NSPoint(x: x, y: y - arm))
        plus.line(to: NSPoint(x: x, y: y + arm))
        plus.lineWidth = 1.3
        plus.lineCapStyle = .round
        NSColor(white: 1, alpha: 0.45).setStroke()
        plus.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let i = Int(convert(event.locationInWindow, from: nil).x / max(slot, 1))
        if i < count { onSelect?(max(i, 0)) } else { onAdd?() }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "Note \(current + 1) of \(count). Press for a new note" }
    override func accessibilityPerformPress() -> Bool {
        onAdd?()
        return true
    }
}

// MARK: - Arrow-only text view (the app never changes the cursor)

class ArrowTextView: NSTextView {
    override func resetCursorRects() { addCursorRect(visibleRect, cursor: .arrow) }
    override func cursorUpdate(with event: NSEvent) { NSCursor.arrow.set() }
    override func mouseMoved(with event: NSEvent) { NSCursor.arrow.set() }
}

// MARK: - Fading text field (overflowing text fades out at whichever edge is clipped)

// Vertically centres the text and uses the same rect for drawing and editing,
// so the text doesn't jump when the field editor takes over on click
final class CenteredCell: NSTextFieldCell {
    private static let editor: ArrowTextView = {
        let e = ArrowTextView()
        e.isFieldEditor = true
        return e
    }()

    override func fieldEditor(for controlView: NSView) -> NSTextView? { Self.editor }

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

        font = .systemFont(ofSize: 11)
        textColor = inkColor
        isBezeled = false
        drawsBackground = false
        focusRingType = .none

        wantsLayer = true
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.mask = fade
        NotificationCenter.default.addObserver(self, selector: #selector(editorChanged(_:)),
                                               name: NSTextView.didChangeSelectionNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // Drop an unfinished edit and show `text` instead
    func reset(to text: String) {
        if currentEditor() != nil { abortEditing() }
        stringValue = text
        updateFades()
    }

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

    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); updateFades() }
    override func textDidChange(_ notification: Notification) { super.textDidChange(notification); updateFadesSoon() }
    override func textDidEndEditing(_ notification: Notification) { super.textDidEndEditing(notification); updateFadesSoon() }
}

// MARK: - Font size field (type a size, click the arrows, scroll, or press ↑ / ↓)

// Stacked up / down chevrons at the right end of the font size field
private final class StepArrows: NSView {
    var onStep: ((CGFloat) -> Void)?
    private var pressed: CGFloat = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let cx = bounds.midX, w: CGFloat = 3, h: CGFloat = 2
        for dir in [CGFloat(1), -1] {
            let cy = bounds.midY + dir * 2.5
            let p = NSBezierPath()
            p.move(to: NSPoint(x: cx - w, y: cy - dir * h / 2))
            p.line(to: NSPoint(x: cx, y: cy + dir * h / 2 + dir))
            p.line(to: NSPoint(x: cx + w, y: cy - dir * h / 2))
            p.lineWidth = 1.4
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            NSColor(white: pressed == dir ? 1 : 0.7, alpha: 1).setStroke()
            p.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        pressed = convert(event.locationInWindow, from: nil).y >= bounds.midY ? 1 : -1
        onStep?(pressed)
    }

    override func mouseUp(with event: NSEvent) { pressed = 0 }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class FontSizeField: NSView, NSTextFieldDelegate {
    var onChange: ((CGFloat) -> Void)?
    var onReturn: (() -> Void)?
    private var value: CGFloat
    private let range: ClosedRange<CGFloat>
    private let field: FadingField
    private var scrolled: CGFloat = 0
    private var text: String { "\(Int(value))" }

    init(value: CGFloat, range: ClosedRange<CGFloat>) {
        self.value = value
        self.range = range
        let frame = CGRect(x: 0, y: 0, width: 40, height: toolH), arrowsW: CGFloat = 14
        field = FadingField(frame: CGRect(x: 4, y: 0, width: frame.width - 4 - arrowsW, height: toolH))
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor

        let arrows = StepArrows(frame: CGRect(x: frame.width - arrowsW, y: 0, width: arrowsW, height: toolH))
        arrows.onStep = { [weak self] in self?.step(by: $0) }
        addSubview(arrows)

        field.alignment = .center
        field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        field.stringValue = text
        field.target = self
        field.action = #selector(commit)
        field.delegate = self
        field.setAccessibilityLabel("Font Size")
        addSubview(field)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func set(_ v: CGFloat) {
        value = min(max(v.rounded(), range.lowerBound), range.upperBound)
        field.stringValue = text
        onChange?(value)
    }

    private func step(by delta: CGFloat) {
        cancel()
        set(value + delta)
    }

    // Drop an unfinished edit
    func cancel() { field.reset(to: text) }

    // Return (or leaving the field) applies the typed size; anything that isn't a number reverts
    @objc private func commit() {
        if let typed = Double(field.stringValue.trimmingCharacters(in: .whitespaces)) { set(CGFloat(typed)) }
        else { field.stringValue = text }
        if let e = NSApp.currentEvent, e.type == .keyDown, e.keyCode == 36 || e.keyCode == 76 { onReturn?() }
    }

    // Scroll over the field: one step per wheel notch, or per ~12pt of trackpad travel
    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began { scrolled = 0 }
        guard event.momentumPhase == [] else { return }   // no coasting past the size you stopped on
        scrolled += event.scrollingDeltaY
        let unit: CGFloat = event.hasPreciseScrollingDeltas ? 12 : 1
        while abs(scrolled) >= unit {
            step(by: scrolled > 0 ? 1 : -1)
            scrolled -= scrolled > 0 ? unit : -unit
        }
    }

    // ↑ / ↓ while editing step from whatever has been typed so far
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let delta: CGFloat
        switch selector {
        case #selector(NSResponder.moveUp(_:)): delta = 1
        case #selector(NSResponder.moveDown(_:)): delta = -1
        default: return false
        }
        set((Double(textView.string).map { CGFloat($0) } ?? value) + delta)
        textView.string = text
        textView.selectAll(nil)
        return true
    }
}

// MARK: - Resize grip (bottom corners)

final class ResizeHandle: NSView {
    weak var wc: NotchWindowController?
    private let isRight: Bool
    private var startMouse = NSPoint.zero
    private var startSize = CGSize.zero
    private var hovering = false { didSet { needsDisplay = true } }
    private var dragging = false { didSet { needsDisplay = true } }

    init(right: Bool) {
        isRight = right
        super.init(frame: CGRect(x: 0, y: 0, width: 28, height: 28))
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError() }

    // Curved grabber running along the centre of the black border, parallel to the panel's corner
    private lazy var grabber: CGPath = {
        let d = webInset / 2, tail: CGFloat = 2
        func at(_ p: CGPoint) -> CGPoint { CGPoint(x: isRight ? bounds.width - p.x : p.x, y: p.y) }
        let path = CGMutablePath()
        path.move(to: at(CGPoint(x: d, y: expandedRadius + tail)))
        cornerCurve(radius: expandedRadius, inset: d).forEach { path.addLine(to: at($0)) }
        path.addLine(to: at(CGPoint(x: expandedRadius + tail, y: d)))
        return path
    }()

    // Only a band around the grabber resizes; the rest of the corner square belongs to the content
    private lazy var hitArea = grabber.copy(strokingWithWidth: 12, lineCap: .round, lineJoin: .round, miterLimit: 1)

    private func onGrabber(_ event: NSEvent) -> Bool { hitArea.contains(convert(event.locationInWindow, from: nil)) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        hitArea.contains(convert(point, from: superview)) ? self : nil
    }

    // Shown on hover / drag
    override func draw(_ dirtyRect: NSRect) {
        guard hovering || dragging, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.addPath(grabber)
        ctx.setLineWidth(2.5)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(NSColor(white: 1, alpha: dragging ? 0.75 : 0.5).cgColor)
        ctx.strokePath()
    }

    override func mouseEntered(with event: NSEvent) { hovering = onGrabber(event) }
    override func mouseMoved(with event: NSEvent) { hovering = onGrabber(event) }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        dragging = true
        startMouse = NSEvent.mouseLocation
        startSize = wc?.panelSize ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        // Width grows on both sides so the panel stays centered on the notch
        wc?.resizePanel(to: CGSize(width: startSize.width + (p.x - startMouse.x) * (isRight ? 2 : -2),
                                   height: startSize.height + startMouse.y - p.y))
    }

    override func mouseUp(with event: NSEvent) {
        dragging = false
        hovering = onGrabber(event)
        wc?.savePanelSize()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Page-load progress: a pill under the web page that widens from the centre

final class LoadingPill: NSView {
    private let pill = CALayer()
    private let pillH: CGFloat = 3, minW: CGFloat = 20
    private var maxW: CGFloat = 0
    private var progress: CGFloat = 0
    private var shown = false
    private var failed = false
    private var failureID = 0   // ignores the fade-out of a failure that a newer load has replaced

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        pill.backgroundColor = NSColor.controlAccentColor.cgColor
        pill.cornerRadius = pillH / 2
        pill.opacity = 0
        layer?.addSublayer(pill)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func apply(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        pill.bounds = CGRect(x: 0, y: 0, width: minW + max(maxW - minW, 0) * progress, height: pillH)
        pill.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    // Where the pill sits and how wide it gets at 100%, in the superview's coordinates.
    // The view covers just that strip under the page, never the page itself.
    func setTrack(center: CGPoint, maxWidth: CGFloat) {
        maxW = maxWidth
        frame = CGRect(x: center.x - maxWidth / 2, y: center.y - pillH / 2, width: max(maxWidth, 0), height: pillH)
        apply(animated: false)
    }

    // Starts small at the bottom centre and widens as the page loads; nil fills it out and fades it
    func setProgress(_ value: Double?) {
        guard !failed else { return }           // a failed load keeps its red bar until it fades
        if let value {
            if !shown {
                shown = true
                progress = 0
                apply(animated: false)
            }
            progress = CGFloat(min(max(value, 0), 1))
            pill.opacity = 1
        } else if shown {
            shown = false
            progress = 1
            pill.opacity = 0
        } else { return }
        apply(animated: true)
    }

    // The page couldn't be loaded: the bar fills out in red, holds for a second, then fades
    func setFailed() {
        failed = true
        shown = false
        progress = 1
        pill.backgroundColor = NSColor.systemRed.cgColor
        pill.opacity = 1
        apply(animated: true)

        failureID += 1
        let id = failureID
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) { [weak self] in   // 0.25s fill + 1s hold
            guard let self, self.failed, self.failureID == id else { return }
            self.failed = false
            self.pill.opacity = 0
        }
    }

    // A new load is starting, or the page was closed
    func reset() {
        failed = false
        shown = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pill.backgroundColor = NSColor.controlAccentColor.cgColor
        pill.opacity = 0
        CATransaction.commit()
    }
}
