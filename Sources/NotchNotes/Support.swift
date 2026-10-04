import Cocoa

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
let toolW:     CGFloat = 24
let toolH:     CGFloat = 20
let toolGap:   CGFloat = 6                  // between neighbouring controls
let trayPad:   CGFloat = 6
let notchGap:  CGFloat = 8
let clearW:    CGFloat = 16                 // clear button inside the URL field
let webInset:  CGFloat = 6                  // black border around web pages
let inkColor = NSColor(white: 0.92, alpha: 1)    // notes and field text
let topLevel = Int(CGWindowLevelForKey(.maximumWindow))   // same level as Teams' share border

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
