# NotchNotes

**A notepad that lives in your MacBook's notch.**

Hover over the notch and a panel drops down with your notes, a checklist or any web page. Move away and it disappears. There is no Dock icon, no menu bar icon and no window to manage.

[Features](#features) · [Install](#install) · [Usage](#usage) · [Your notes](#your-notes) · [Build from source](#build-from-source)

https://github.com/user-attachments/assets/21a1e01f-e46a-49fc-b3f6-b9cb442a801e

**Requirements:** macOS 13 Ventura or later. Designed for Macs with a notch; on other Macs the panel sits at the top center of the screen.

## Features

### Notes

- **Saved as you type**: notes are plain text files, restored the next time the app opens.
- **Several notes**: the dots under the text switch between notes, and `+` starts a new one.
- **Checklists**: type `- [ ] item` or use the checklist button. Click a box to check it; checked items are struck through and move below the unchecked ones.
- **Numbered and bulleted lists**: Enter continues the list and keeps the numbers in order. Tab and Shift-Tab move an item in or out a level.
- **Links**: addresses in your notes are underlined. ⌘-click one to open it in the panel.
- **Font size**: set the editor font from 10 to 24 pt in the toolbar.

### Web pages

- **Any page in the panel**: type an address in the URL field and press Return. Text that isn't an address runs a web search. The page is remembered across launches.
- **Mobile or desktop site**: one button switches between the two.
- **Audio indicator**: a page keeps playing after the panel closes, and a thin line pulses around the notch while it does.
- **Downloads**: files are saved to your Downloads folder.
- **Local addresses**: `localhost`, `.local` and bare IP addresses load over `http`.
- **Light and dark**: pages follow the system appearance. The panel itself is always dark.

### The panel

- **Opens on hover or by hotkey**: rest the mouse on the notch, or press ⌃⌥N from any app.
- **Lock open**: the lock button keeps the panel open when the mouse leaves, and stays set across launches.
- **Resizable**: drag either bottom corner. The size is remembered.
- **Hidden from screen sharing**: by default the panel is left out of screen recordings and screen shares. The eye button shows it.
- **Stays in front**: the panel returns to the front when another app's overlay, such as a screen-share border, covers it.
- **Fits any width**: toolbar buttons that don't fit move into a `…` tray.
- **Follows your displays**: the panel moves with the notch when displays are added, removed or rearranged.
- **Accessible**: toolbar buttons and fields are labelled for VoiceOver.

### Updates

NotchNotes checks its GitHub releases at launch. When a newer version is available, a cloud button appears next to the quit button; hover it to see the version. Click it and the app downloads the release, replaces itself and relaunches.

The button goes away once the panel has been open for a minute, and returns at the next launch.

## Install

1. Download `NotchNotes-vX.Y.Z.zip` from the [latest release](https://github.com/devadula-nandan/NotchNotes/releases/latest).
2. Unzip it and move `NotchNotes.app` to `/Applications`.
3. Clear the macOS quarantine flag. This is needed once, because the app is ad-hoc signed rather than notarized:
   ```bash
   xattr -cr /Applications/NotchNotes.app
   ```
4. Open the app and hover over the notch.

Later versions arrive through the [update button](#updates), so these steps are not repeated.

**Start at login (optional):** System Settings → General → Login Items → **+** → select `NotchNotes.app`.

## Usage

| Action | How |
|---|---|
| Open the panel | Hover over the notch, or press ⌃⌥N |
| Close the panel | Move the mouse away, press ⌃⌥N, or press Esc while in the notes |
| New note | Click `+` after the dots, or press ⌘N |
| Switch notes | Click a dot, or press ⌘⇧[ / ⌘⇧] |
| Check or uncheck an item | Click its box |
| Indent a list item | Tab / Shift-Tab |
| Open a link from the notes | ⌘-click it |
| Go to the URL field | ⌘L |
| Load a page | Type an address or a search, then press Return |
| Back, forward, reload | ⌘[ / ⌘] / ⌘R |
| Return to the notes | Click × in the URL field, or clear the field and press Return |
| Resize the panel | Drag either bottom corner |
| Quit | Click the red dot in the top left, or press ⌘Q |

The standard editing shortcuts (⌘A, ⌘C, ⌘V, ⌘X, ⌘Z, ⌘⇧Z) work as usual.

## Your notes

Notes are plain text files in `~/Library/Application Support/NotchNotes`: `notes.txt`, then `notes-2.txt`, `notes-3.txt` and so on.

- The first save of each launch keeps the previous version as `notes.txt.bak`.
- A file that can't be read is never saved over.
- A note left empty is removed.

To keep the notes somewhere else, such as a synced folder, set the folder and relaunch:

```bash
defaults write com.local.notchnotes notesFolder ~/path/to/folder
```

## Build from source

Requires [Swift](https://swift.org), which ships with Xcode and the Xcode Command Line Tools.

```bash
git clone https://github.com/devadula-nandan/NotchNotes.git
cd NotchNotes
bash make-app.sh      # release build, ad-hoc signed
open NotchNotes.app
```

| Script | What it does |
|---|---|
| `bash make-app.sh` | Builds a self-contained `NotchNotes.app` in the project root. |
| `bash dev.sh` | Builds in debug mode, launches the app, and rebuilds and relaunches it when a file under `Sources/` or `Package.swift` changes. A failed build leaves the previous one running. It quits an installed `NotchNotes.app` first, since both would share the same notes. Ctrl+C stops it. |
| `bash test.sh` | Runs the tests for the text, address and storage logic in `Sources/NotchNotesCore`. With full Xcode installed, `swift test` works as well. |

## License

MIT. See [LICENSE](LICENSE).
