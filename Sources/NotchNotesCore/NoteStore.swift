import Foundation

// The notes on disk: "notes.txt", then "notes-2.txt", "notes-3.txt", … in one folder
public final class NoteStore {
    public let folder: URL
    public private(set) var files: [URL] = []
    private var backedUp: Set<String> = []
    private let fm = FileManager.default

    public init(folder: URL) {
        self.folder = folder
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let found = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        files = found.filter { Self.number(of: $0.lastPathComponent) != nil }
            .sorted { Self.number(of: $0.lastPathComponent)! < Self.number(of: $1.lastPathComponent)! }
        if files.isEmpty { files = [folder.appendingPathComponent("notes.txt")] }
    }

    // "notes.txt" is 1, "notes-7.txt" is 7; anything else isn't a note
    static func number(of name: String) -> Int? {
        if name == "notes.txt" { return 1 }
        guard name.hasPrefix("notes-"), name.hasSuffix(".txt") else { return nil }
        let digits = name.dropFirst(6).dropLast(4)
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(digits), n > 1 else { return nil }
        return n
    }

    public var count: Int { files.count }

    public func name(at index: Int) -> String { files[index].lastPathComponent }

    public func index(named name: String) -> Int? { files.firstIndex { $0.lastPathComponent == name } }

    // A note that isn't on disk yet is empty; one that is there but can't be read throws,
    // so the caller doesn't mistake it for empty and save over it
    public func read(at index: Int) throws -> String {
        let url = files[index]
        guard fm.fileExists(atPath: url.path) else { return "" }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func write(_ text: String, at index: Int) throws {
        let url = files[index], exists = fm.fileExists(atPath: url.path)
        if text.isEmpty, !exists { return }

        // Before the first save of each launch, what was on disk is kept as "<name>.bak".
        // An empty file is not worth keeping, and would replace a backup that is
        if exists, backedUp.insert(url.lastPathComponent).inserted,
           let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 0 {
            let backup = url.appendingPathExtension("bak")
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: url, to: backup)
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // A new note after the last one; its file appears once something is written to it
    public func add() -> Int {
        let n = (files.compactMap { Self.number(of: $0.lastPathComponent) }.max() ?? 1) + 1
        files.append(folder.appendingPathComponent("notes-\(n).txt"))
        return files.count - 1
    }

    // The last remaining note is never removed
    public func remove(at index: Int) {
        guard files.count > 1 else { return }
        try? fm.removeItem(at: files[index])
        files.remove(at: index)
    }
}
