import Cocoa
import Carbon.HIToolbox

// MARK: - Persistence

// Where the notes are kept. `defaults write com.local.notchnotes notesFolder <path>` moves them,
// for example into a synced folder
let notesFolder: URL = {
    if let custom = UserDefaults.standard.string(forKey: "notesFolder"), !custom.isEmpty {
        return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
    }
    return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NotchNotes")
}()

func stored(_ key: String, default value: CGFloat) -> CGFloat {
    let v = UserDefaults.standard.double(forKey: key)
    return v > 0 ? CGFloat(v) : value
}

func store(_ value: CGFloat, _ key: String) {
    UserDefaults.standard.set(Double(value), forKey: key)
}

// MARK: - Notch geometry

// Without a notch it is the primary screen (the one with the menu bar). Not NSScreen.main: that one
// follows keyboard focus, which would move the panel between screens
var notchScreen: NSScreen {
    NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first ?? NSScreen.main ?? NSScreen()
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
let hoverDelay:      TimeInterval = 0.1     // how long the mouse rests on the notch before the panel opens
let edgeInset: CGFloat = 12                 // quit / eye distance from the side edges
let toolW:     CGFloat = 24
let toolH:     CGFloat = 20
let toolGap:   CGFloat = 6                  // between neighbouring controls
let trayPad:   CGFloat = 6
let notchGap:  CGFloat = 8
let clearW:    CGFloat = 16                 // clear button inside the URL field
let webInset:  CGFloat = 6                  // black border around web pages
let inkColor = NSColor(white: 0.92, alpha: 1)    // notes and field text
let topLevel = Int(CGWindowLevelForKey(.maximumWindow))   // same level as Teams' share border
let hotKeyCode = UInt32(kVK_ANSI_N)                       // ⌃⌥N opens and closes the panel from anywhere
let hotKeyModifiers = UInt32(controlKey | optionKey)

// Corner radius of the notch shape at a given window height (grows as it expands)
func shapeRadius(height h: CGFloat, fullHeight: CGFloat) -> CGFloat {
    let nh = notchSize.height
    let t = max(0, min(1, (h - nh) / max(fullHeight - nh, 1)))
    return collapsedRadius + (expandedRadius - collapsedRadius) * t
}

// The panel's bottom-left corner curve moved `inset` points inward, so the band between the two has
// the same thickness all the way round. Corner at the origin; runs from the left edge to the bottom edge.
// (The corner is a quadratic curve, not a circle, so a plain rounded rect doesn't stay parallel to it.)
func cornerCurve(radius r: CGFloat, inset d: CGFloat, steps: Int = 24) -> [CGPoint] {
    (0...steps).map { i in
        let t = CGFloat(i) / CGFloat(steps), u = 1 - t
        let n = (u * u + t * t).squareRoot()
        return CGPoint(x: t * t * r + d * u / n, y: u * u * r + d * t / n)
    }
}

// MARK: - Global hotkey

// A system-wide key combination. Carbon hotkeys need no accessibility permission
final class HotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        // Fails quietly if another app already has the combination
        RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: OSType(0x4E_4F_54_43), id: 1),
                            GetApplicationEventTarget(), 0, &hotKey)
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
