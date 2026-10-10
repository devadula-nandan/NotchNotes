import Cocoa

// Over-the-air updates: the app looks at its GitHub releases when it starts and can replace itself with a newer
// one, so there is nothing to download, move or un-quarantine by hand
enum OTA {
    private static let latest = URL(string: "https://api.github.com/repos/devadula-nandan/notch-notes/releases/latest")!

    // Calls back with the latest release when it is newer than this app: its tag and the zip of the app.
    // Stays quiet otherwise, also in a dev build, which has no version of its own
    static func check(_ found: @escaping (_ tag: String, _ zip: URL) -> Void) {
        guard let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return }
        URLSession.shared.dataTask(with: latest) { data, _, _ in
            guard let data, let release = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = release["tag_name"] as? String,
                  tag.dropFirst().compare(current, options: .numeric) == .orderedDescending,
                  let asset = (release["assets"] as? [[String: Any]])?.first?["browser_download_url"] as? String,
                  let zip = URL(string: asset) else { return }
            DispatchQueue.main.async { found(tag, zip) }
        }.resume()
    }

    // Fetches the zip, unpacks it over this app and starts the new copy once this one has quit.
    // `failed` is called instead when a step goes wrong, with the app left as it was
    static func install(_ zip: URL, failed: @escaping () -> Void) {
        let app = Bundle.main.bundleURL
        URLSession.shared.downloadTask(with: zip) { file, _, _ in
            do {
                guard let file else { throw CocoaError(.fileNoSuchFile) }
                let dir = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                      appropriateFor: app, create: true)
                let unzip = try Process.run(URL(fileURLWithPath: "/usr/bin/ditto"), arguments: ["-x", "-k", file.path, dir.path])
                unzip.waitUntilExit()
                guard unzip.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
                _ = try FileManager.default.replaceItemAt(app, withItemAt: dir.appendingPathComponent("NotchNotes.app"))
                // Two copies at once would fight over the hotkey, so the new one waits for this one to go
                try Process.run(URL(fileURLWithPath: "/bin/sh"),
                                arguments: ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; open \"$0\"", app.path])
                DispatchQueue.main.async { NSApp.terminate(nil) }
            } catch {
                DispatchQueue.main.async(execute: failed)
            }
        }.resume()
    }
}
