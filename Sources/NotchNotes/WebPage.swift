import Cocoa
import WebKit
import NotchNotesCore

// The web page shown in place of the notes, its pop-ups, dialogs and downloads

extension NotchWindowController {
    // MARK: - Web page

    @objc func urlEntered() {
        setWebURL(urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        closeTray()
        focusContent()
    }

    // Non-empty text shows a web page (or a search for it); empty returns to the notes
    func setWebURL(_ text: String) {
        popups.forEach(discard)
        popups = []
        if !text.isEmpty, let url = NotchNotesCore.destination(for: text) {
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

    func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        // Keep the arrow over links, text and inputs in the page too
        config.userContentController.addUserScript(WKUserScript(
            source: "const s = document.createElement('style'); s.textContent = '* { cursor: default !important; }'; document.documentElement.appendChild(s);",
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        // Add the browser token the embedded engine leaves out, so sites serve the pages a full browser gets
        config.applicationNameForUserAgent = "Version/\(browserVersion) Safari/605.1.15"

        let wv = WKWebView(frame: .zero, configuration: config)
        webView = wv
        adopt(wv)
        return wv
    }

    // Set-up shared by the page and its pop-ups
    func adopt(_ wv: WKWebView) {
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
                                                 wv.observe(\.url) { [weak self] wv, _ in self?.pageURLChanged(wv) },
                                                 wv.observe(\.isPlayingSound) { [weak self] _, _ in self?.updateSoundLine() }]
    }

    // A window the page opens from script (sign-in pop-ups mostly) covers the page until it closes itself or
    // is closed with the × in the URL field. The page stays loaded underneath, so the two can still talk
    func openPopup(_ configuration: WKWebViewConfiguration) -> WKWebView {
        let wv = WKWebView(frame: .zero, configuration: configuration)
        popups.append(wv)
        adopt(wv)
        showTopWeb()
        return wv
    }

    func closePopup(_ wv: WKWebView) {
        guard let i = popups.firstIndex(of: wv) else { return }
        popups.remove(at: i)
        discard(wv)
        showTopWeb()
        updateSoundLine()   // the sound may have been its own
    }

    // Only the topmost web view is visible; the URL field, its × and the loading pill follow it
    func showTopWeb() {
        let top = shownWeb
        for wv in allWebViews where wv !== top { wv.isHidden = true }
        top?.isHidden = false
        urlField.reset(to: shownAddress)
        loadingPill.reset()
        if let top, top.isLoading { loadingPill.setProgress(top.estimatedProgress) }
        layoutControls()
        focusContent()
    }

    func discard(_ wv: WKWebView) {
        webObservations[ObjectIdentifier(wv)] = nil
        wv.navigationDelegate = nil          // a load still in flight must not report back after closing
        wv.stopLoading()
        wv.removeFromSuperview()
    }

    func closeWebView() {
        allWebViews.forEach(discard)
        popups = []
        webView = nil
        loadingPill.reset()
    }

    func pageURLChanged(_ wv: WKWebView) {
        guard let url = wv.url, url.scheme == "http" || url.scheme == "https" else { return }
        if wv === webView { webURL = url.absoluteString }
        if wv === shownWeb, urlField.currentEditor() == nil {
            urlField.stringValue = url.absoluteString
            urlField.updateFades()
        }
    }

    // Web pages see the system's light/dark setting via prefers-color-scheme
    func applySystemTheme() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        allWebViews.forEach { $0.appearance = NSAppearance(named: dark ? .darkAqua : .aqua) }
    }

    var browserVersion: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return os >= 26 ? "\(os).0" : "18.5"
    }

    // A phone browser's agent, so sites serve their mobile pages; nil falls back to the desktop agent.
    // From iOS 26 on the OS version in it stays at 18_6 and only Version/ moves on
    var mobileUserAgent: String {
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) "
            + "Version/\(browserVersion) Mobile/15E148 Safari/604.1"
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
    func ask(_ message: String, input: String? = nil, cancel: Bool = false,
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

// MARK: - Sound

extension WKWebView {
    // Whether the page is making sound right now (playing and not muted). WebKit only keeps this in an
    // internal property; should a later version drop it, every page simply counts as silent
    @objc dynamic var isPlayingSound: Bool {
        responds(to: NSSelectorFromString("_isPlayingAudio")) && value(forKey: "_isPlayingAudio") as? Bool == true
    }

    // Makes `isPlayingSound` observable: it changes whenever WebKit's own property does
    @objc class func keyPathsForValuesAffectingIsPlayingSound() -> Set<String> { ["_isPlayingAudio"] }
}
