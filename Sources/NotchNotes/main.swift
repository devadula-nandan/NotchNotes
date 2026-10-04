import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var wc: NotchWindowController!

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
