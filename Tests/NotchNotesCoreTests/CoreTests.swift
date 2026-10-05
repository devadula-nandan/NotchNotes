import Foundation
import Testing
@testable import NotchNotesCore

@Suite struct AddressTests {
    @Test func addressesGetHTTPS() {
        #expect(destination(for: "example.com")?.absoluteString == "https://example.com")
        #expect(destination(for: "example.com/a?b=1")?.absoluteString == "https://example.com/a?b=1")
    }

    @Test func localAddressesGetHTTP() {
        #expect(destination(for: "localhost:3000")?.absoluteString == "http://localhost:3000")
        #expect(destination(for: "localhost")?.absoluteString == "http://localhost")
        #expect(destination(for: "192.168.1.5:8080/x")?.absoluteString == "http://192.168.1.5:8080/x")
        #expect(destination(for: "my-mac.local")?.absoluteString == "http://my-mac.local")
        #expect(destination(for: "1.2.3.4.5")?.scheme == "https")
    }

    @Test func schemesAreKept() {
        #expect(destination(for: "https://localhost:3000")?.absoluteString == "https://localhost:3000")
        #expect(destination(for: "http://example.com")?.absoluteString == "http://example.com")
    }

    @Test func anythingElseIsASearch() {
        let url = destination(for: "swift text view")
        #expect(url?.host == "www.google.com")
        #expect(URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "swift text view")
        #expect(destination(for: "hello")?.host == "www.google.com")
    }
}

@Suite struct ListTextTests {
    @Test func toggleAddsAndRemovesCheckboxes() {
        let on = ListText.toggled("a\nb\n", kind: .checkbox)
        #expect(on.text == "- [ ] a\n- [ ] b\n")
        #expect(!on.removing)
        let off = ListText.toggled(on.text, kind: .checkbox)
        #expect(off.text == "a\nb\n")
        #expect(off.removing)
    }

    @Test func toggleNumbersLinesAndSkipsBlanks() {
        #expect(ListText.toggled("a\n\n  b", kind: .numbered).text == "1. a\n\n  2. b")
    }

    @Test func toggleSwitchesKind() {
        #expect(ListText.toggled("- [x] a\n- b", kind: .numbered).text == "1. a\n2. b")
    }

    @Test func toggleOnABlankLineStartsAList() {
        #expect(ListText.toggled("", kind: .checkbox).text == "- [ ] ")
    }

    @Test func renumberFixesFollowingItems() {
        let text = "1. a\n1. b\n5. c\nplain\n9. d"
        let edits = ListText.renumbering(text, after: 0)
        #expect(edits.map(\.number) == ["2", "3"])
        var s = text as NSString
        for e in edits.reversed() { s = s.replacingCharacters(in: e.range, with: e.number) as NSString }
        #expect(s as String == "1. a\n2. b\n3. c\nplain\n9. d")
    }

    @Test func renumberStopsAtAnotherIndent() {
        #expect(ListText.renumbering("1. a\n  1. b\n7. c", after: 0).isEmpty)
        #expect(ListText.renumbering("plain\n4. a", after: 0).isEmpty)
    }

    @Test func renumberGrowsNumbers() {
        let edits = ListText.renumbering("9. a\n9. b", after: 0)
        #expect(edits.count == 1)
        #expect(edits[0].number == "10")
    }

    @Test func indentMovesOnlyListItems() {
        #expect(ListText.indented("- [ ] a\nplain\n1. b\n", outdent: false) == "  - [ ] a\nplain\n  1. b\n")
        #expect(ListText.indented("  - a\n\t- b\n - c\n- d", outdent: true) == "- a\n- b\n- c\n- d")
        #expect(ListText.indented("plain\n", outdent: false) == nil)
    }

    @Test func restyleRangeCoversNeighbouringLines() {
        let text = "ab\ncd\nef" as NSString
        // Typing inside "cd" restyles just that line
        #expect(ListText.restyleRange(in: text, editedAt: 4, length: 1) == NSRange(location: 3, length: 3))
        // A line break put in at the end of "ab" also restyles the line it pushed down
        #expect(ListText.restyleRange(in: text, editedAt: 2, length: 1) == NSRange(location: 0, length: 6))
        // Deleting at the very end
        #expect(ListText.restyleRange(in: text, editedAt: 8, length: 0) == NSRange(location: 6, length: 2))
        #expect(ListText.restyleRange(in: "", editedAt: 0, length: 0) == NSRange(location: 0, length: 0))
    }
}

@Suite struct NoteStoreTests {
    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("NotchNotesTests-\(UUID().uuidString)")
    }

    @Test func startsWithOneEmptyNote() throws {
        let store = NoteStore(folder: folder())
        #expect(store.count == 1)
        #expect(store.name(at: 0) == "notes.txt")
        #expect(try store.read(at: 0) == "")
    }

    @Test func notesAreOrderedByNumber() throws {
        let dir = folder()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["notes-10.txt", "notes.txt", "notes-2.txt", "notes.txt.bak", "other.txt", "notes-x.txt"] {
            try name.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let store = NoteStore(folder: dir)
        #expect(store.files.map(\.lastPathComponent) == ["notes.txt", "notes-2.txt", "notes-10.txt"])
        #expect(store.add() == 3)
        #expect(store.name(at: 3) == "notes-11.txt")
    }

    @Test func unreadableNoteThrowsInsteadOfReadingEmpty() throws {
        let dir = folder()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data([0xFF, 0xFE, 0xFF]).write(to: dir.appendingPathComponent("notes.txt"))
        let store = NoteStore(folder: dir)
        #expect(throws: (any Error).self) { try store.read(at: 0) }
    }

    @Test func firstSaveKeepsABackup() throws {
        let dir = folder()
        let store = NoteStore(folder: dir)
        try store.write("one", at: 0)
        let backup = dir.appendingPathComponent("notes.txt.bak")
        #expect(!FileManager.default.fileExists(atPath: backup.path))

        let next = NoteStore(folder: dir)          // the next launch
        try next.write("two", at: 0)
        try next.write("three", at: 0)
        #expect(try String(contentsOf: backup, encoding: .utf8) == "one")
        #expect(try next.read(at: 0) == "three")

        // A wiped file doesn't replace a good backup
        try next.write("", at: 0)
        try NoteStore(folder: dir).write("four", at: 0)
        #expect(try String(contentsOf: backup, encoding: .utf8) == "one")
    }

    @Test func emptyNewNoteLeavesNoFileAndRemoveKeepsTheLast() throws {
        let dir = folder()
        let store = NoteStore(folder: dir)
        try store.write("a", at: 0)
        let i = store.add()
        try store.write("", at: i)
        #expect(!FileManager.default.fileExists(atPath: store.files[i].path))
        store.remove(at: i)
        store.remove(at: 0)
        #expect(store.count == 1)
        #expect(try store.read(at: 0) == "a")
    }
}
