import Foundation

/// Lines one edit added and removed in a file.
public struct FileChange: Equatable, Sendable {
    public let path: String
    public let added: Int
    public let removed: Int

    public init(path: String, added: Int, removed: Int) {
        self.path = path
        self.added = added
        self.removed = removed
    }

    /// Counts the lines between the common start and end of both texts, like a diff hunk.
    static func lines(old: String, new: String) -> (added: Int, removed: Int) {
        let before = split(old)
        let after = split(new)
        var start = 0
        while start < min(before.count, after.count), before[start] == after[start] { start += 1 }
        var end = 0
        while end < min(before.count, after.count) - start,
            before[before.count - 1 - end] == after[after.count - 1 - end]
        {
            end += 1
        }
        return (after.count - start - end, before.count - start - end)
    }

    /// A file's final newline ends its last line rather than starting another.
    private static func split(_ text: String) -> [Substring] {
        let body = text.hasSuffix("\n") ? text.dropLast() : Substring(text)
        return text.isEmpty ? [] : body.split(separator: "\n", omittingEmptySubsequences: false)
    }
}

/// What an agent changed during its current turn, for "3 files +120 −14" when it's done.
public struct ChangeSummary: Equatable, Sendable {
    private var paths: Set<String> = []
    public private(set) var added = 0
    public private(set) var removed = 0

    public init() {}

    public var files: Int { paths.count }
    public var isEmpty: Bool { paths.isEmpty }

    public mutating func record(_ change: FileChange) {
        paths.insert(change.path)
        added += change.added
        removed += change.removed
    }
}

/// The parts of an edit tool's input needed to count lines.
struct EditToolPayload: Decodable {
    struct Edit: Decodable {
        let oldString: String
        let newString: String

        enum CodingKeys: String, CodingKey {
            case oldString = "old_string"
            case newString = "new_string"
        }
    }

    let filePath: String?
    let oldString: String?
    let newString: String?
    let content: String?
    let edits: [Edit]?

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case oldString = "old_string"
        case newString = "new_string"
        case content
        case edits
    }

    static func change(tool: String?, input: EditToolPayload?) -> FileChange? {
        guard let input, let path = input.filePath else { return nil }
        let pairs: [(String, String)]
        switch tool {
        case "Edit":
            guard let old = input.oldString, let new = input.newString else { return nil }
            pairs = [(old, new)]
        case "MultiEdit":
            pairs = (input.edits ?? []).map { ($0.oldString, $0.newString) }
        case "Write":
            // A rewrite of an existing file counts as all new lines; the old text isn't sent.
            pairs = [("", input.content ?? "")]
        default:
            return nil
        }
        let counts = pairs.map { FileChange.lines(old: $0.0, new: $0.1) }
        return FileChange(
            path: path, added: counts.reduce(0) { $0 + $1.added },
            removed: counts.reduce(0) { $0 + $1.removed })
    }
}
