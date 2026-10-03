# NotchNotes

A lightweight macOS menubar notepad that lives inside your MacBook's notch. Hover over the notch to reveal a dark floating panel where you can take notes, manage checklists, or pin any webpage, all without leaving your current app.

> Requires macOS 13 Ventura or later on a Mac with a notch (M-series MacBook Pro/Air). Works on non-notch Macs too, centering at the top of the screen.

---

## Demo

https://github.com/user-attachments/assets/21a1e01f-e46a-49fc-b3f6-b9cb442a801e

---

## Features

- **Lives in the notch**: hovers silently at the top of your screen; expands on mouse-over, disappears when you move away.
- **Persistent notes**: your text is auto-saved to `~/Library/Application Support/NotchNotes/notes.txt` and restored on relaunch.
- **Checkbox lists**: type `- [ ] item` or click the checklist toolbar button to toggle a to-do list. Click any checkbox to check/uncheck it. Checked items are struck through and dimmed automatically.
- **Bullet lists**: one-click bullet-list formatting with the same smart toggle/remove logic.
- **Inline web view**: paste a URL into the URL bar and press Return to embed any webpage in the panel. Press Return on an empty URL field to return to notes. The URL is remembered across relaunches.
- **Resizable panel**: drag the bottom-left or bottom-right corner grips to resize the panel. Width and height are saved and restored.
- **Adjustable font size**: A− / A+ buttons shrink or grow the monospaced editor font (10–24 pt). Persisted across launches.
- **Screen-recording privacy**: by default the window is excluded from screen captures and recordings. Click the eye icon in the top-right to toggle visibility in screen shares.
- **Overflow toolbar tray**: on narrower panels, toolbar buttons collapse into a `…` menu so nothing is ever clipped.
- **Smooth expand/collapse animation**: 220 ms ease-out expand, ease-in collapse with a 150 ms fade.
- **Stays on top**: the panel re-orders above Microsoft Teams' share border and other max-level windows automatically.
- **Keyboard shortcuts**: standard ⌘A, ⌘C, ⌘V, ⌘X, ⌘Z, ⌘⇧Z, ⌘Q all work even though the app has no Dock icon or menu bar.
- **Dark appearance**: panel is always dark; embedded web pages follow the system light/dark setting via `prefers-color-scheme`.
- **No Dock icon, no menu bar icon**: pure accessory app that stays out of your way.

---

## Installation (pre-built, recommended)

1. Go to the [**Releases**](../../releases) page and download **NotchNotes.zip** from the latest release.
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

---

## Usage tips

| Action | How |
|---|---|
| Open the panel | Hover over the notch / top-center |
| Close the panel | Move the mouse away |
| Toggle a checkbox | Click the box, or use the checklist button |
| Load a webpage | Click the URL field, paste a URL, press Return |
| Return to notes | Clear the URL field and press Return |
| Resize | Drag the bottom-left or bottom-right corner grip |
| Quit | Click the red dot in the top-left, or press ⌘Q |

---

## License

MIT
