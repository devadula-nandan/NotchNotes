# NotchNotes

A lightweight macOS notepad that lives inside your MacBook's notch. Hover over the notch to reveal a dark floating panel where you can take notes, manage checklists, or pin any webpage, all without leaving your current app.

> Requires macOS 13 Ventura or later on a Mac with a notch (M-series MacBook Pro/Air). Works on non-notch Macs too, centering at the top of the screen.

---

## Demo

https://github.com/user-attachments/assets/21a1e01f-e46a-49fc-b3f6-b9cb442a801e

---

## Features

- **Lives in the notch**: hovers silently at the top of your screen; expands when the mouse rests on the notch for a moment, disappears when you move away. It follows the notch when displays are added, removed or rearranged.
- **Global hotkey**: ⌃⌥N opens the panel from anywhere, ready to type, and closes it again. Esc closes it too.
- **Persistent notes**: your text is auto-saved to `~/Library/Application Support/NotchNotes/notes.txt` and restored on relaunch. The first save of each launch keeps the previous version as `notes.txt.bak`, and a file that can't be read is never saved over.
- **Several notes**: the dots under the notes switch between them and `+` starts a new one (also ⌘N, ⌘⇧[ and ⌘⇧]). Extra notes are saved as `notes-2.txt`, `notes-3.txt`, … and a note left empty is removed.
- **Notes folder of your choice**: `defaults write com.local.notchnotes notesFolder ~/path/to/folder` keeps the notes somewhere else, such as a synced folder. Relaunch to apply.
- **Checkbox lists**: type `- [ ] item` or click the checklist toolbar button to toggle a to-do list. Click any checkbox to check/uncheck it. Checked items are struck through, dimmed and moved below the unchecked ones in their list automatically.
- **Numbered lists**: one-click numbered-list formatting with the same smart toggle/remove logic. Enter continues the list and keeps the numbers in order.
- **Bullets and indenting**: Enter continues a `- item` list as well. Tab and Shift-Tab move list items in and out a level.
- **Links**: addresses in the notes are underlined; ⌘-click one to open it in the panel.
- **Inline web view**: paste a URL into the URL bar and press Return to embed any webpage in the panel. Plain text that isn't an address runs a web search. Addresses on `localhost`, `.local` or a bare IP load over `http`. Press Return on an empty URL field to return to notes. The URL is remembered across relaunches.
- **Audio indicator**: a page keeps playing after the panel closes. While it is playing audio, a thin line shows around the notch with pulses running up it, so you can tell where the audio is coming from.
- **Lock open**: click the lock icon next to the quit button to keep the panel open when the mouse leaves; click again to unlock. The lock is remembered across relaunches.
- **Resizable panel**: drag the bottom-left or bottom-right corner grips to resize the panel. Width and height are saved and restored.
- **Adjustable font size**: a small number field in the toolbar sets the monospaced editor font size (10–24 pt). Type a size and press Return, or step it with the field's up / down arrows or the ↑ / ↓ keys. Persisted across launches.
- **Screen-recording privacy**: by default the window is excluded from screen captures and recordings. Click the eye icon in the top-right to toggle visibility in screen shares.
- **Overflow toolbar tray**: on narrower panels, toolbar buttons collapse into a `…` menu so nothing is ever clipped.
- **Smooth expand/collapse animation**: 220 ms ease-out expand, ease-in collapse with a 150 ms fade.
- **Updates itself**: at launch the app checks its GitHub releases. When a newer version is out, a cloud button appears in the toolbar for 60 seconds of the panel being open, counting down; hover it to see the version. Click it and the app downloads that release, replaces itself and relaunches, with no manual download or `xattr`.
- **Stays on top**: the panel puts itself back in front when another app's overlay, such as a screen-share border, gets in front of it.
- **Keyboard shortcuts**: standard ⌘A, ⌘C, ⌘V, ⌘X, ⌘Z, ⌘⇧Z, ⌘Q all work even though the app has no Dock icon or menu bar. ⌘L jumps to the URL field; ⌘[, ⌘] and ⌘R go back, forward and reload a page.
- **VoiceOver**: the toolbar buttons and fields are labelled.
- **Dark appearance**: panel is always dark; embedded web pages follow the system light/dark setting via `prefers-color-scheme`.
- **No Dock icon, no menu bar icon**: pure accessory app that stays out of your way.

---

## Installation (pre-built, recommended)

1. Go to the [**Releases**](../../releases) page and download **NotchNotes-vX.Y.Z.zip** from the latest release.
2. Unzip it to get **NotchNotes.app**.
3. Move `NotchNotes.app` to your `/Applications` folder.
4. **First launch:** macOS will block the app with a *"cannot be verified"* warning because it is ad-hoc signed, not notarized. Run this once in Terminal to clear it:
   ```bash
   xattr -cr /Applications/NotchNotes.app
   ```
   Then double-click the app normally. You will not see this prompt again.
5. Hover over the notch (or the top-center of the screen) to confirm it works.
6. Notes are saved in `~/Library/Application Support/NotchNotes`

**Auto-start on login (optional)**  
System Settings → General → Login Items → click **+** → select `NotchNotes.app`.

---

## Build from source

Requires [Swift](https://swift.org) (ships with Xcode or the Xcode Command Line Tools).

```bash
# Clone
git clone https://github.com/devadula-nandan/NotchNotes.git
cd NotchNotes

# Build the .app bundle (compiles in release mode, ad-hoc signs)
bash make-app.sh

# Run it
open NotchNotes.app
```

The script produces a self-contained `NotchNotes.app` in the project root.

### Dev mode

```bash
bash dev.sh
```

Builds in debug mode, launches the app, and rebuilds and relaunches it whenever a file under `Sources/` or `Package.swift` changes. If a build fails, the previous build keeps running. It quits an installed `NotchNotes.app` first, since both would share the same notes file. Press Ctrl+C to stop.

### Tests

```bash
bash test.sh
```

Runs the tests for the text, address and storage logic in `Sources/NotchNotesCore`. With full Xcode installed, `swift test` works as well.

---

## Usage tips

| Action | How |
|---|---|
| Open the panel | Hover over the notch / top-center, or press ⌃⌥N |
| Close the panel | Move the mouse away, or press Esc (in the notes) or ⌃⌥N |
| Switch notes | Click a dot under the notes, or press ⌘⇧[ / ⌘⇧] |
| New note | Click the `+` after the dots, or press ⌘N |
| Indent a list item | Tab / Shift-Tab |
| Open a link in the notes | ⌘-click it |
| Toggle a checkbox | Click the box, or use the checklist button |
| Load a webpage | Click the URL field (or press ⌘L), paste a URL, press Return |
| Return to notes | Clear the URL field and press Return |
| Resize | Drag the bottom-left or bottom-right corner grip |
| Quit | Click the red dot in the top-left, or press ⌘Q |

---

## License

MIT. See [LICENSE](LICENSE).
