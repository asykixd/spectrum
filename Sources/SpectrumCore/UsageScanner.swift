import Foundation

/// Reads every Claude Code transcript under `~/.claude/projects`, subagents included, and keeps
/// what it read so the next scan only parses lines appended since.
public struct UsageScanner: Sendable {
    private struct FileState: Sendable {
        var reader = JSONLReader()
        var log = UsageLog()
        var seen = Set<String>()
    }

    private let root: URL
    private var files: [String: FileState] = [:]

    public init(root: URL) {
        self.root = root
    }

    /// Usage from transcripts touched since `date`; older files can't hold newer lines.
    public mutating func scan(since date: Date) -> UsageLog {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard
            let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys)
        else { return UsageLog() }
        var total = UsageLog()
        var alive = Set<String>()
        let parser = UsageLog.LineParser()
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                let modified = values.contentModificationDate, modified >= date
            else { continue }
            let path = url.path
            alive.insert(path)
            var state = files.removeValue(forKey: path) ?? FileState()
            read(url, into: &state, parser: parser)
            files[path] = state
            total.append(state.log)
        }
        files = files.filter { alive.contains($0.key) }
        return total
    }

    private func read(_ url: URL, into state: inout FileState, parser: UsageLog.LineParser) {
        var reader = state.reader
        defer { state.reader = reader }
        do {
            try reader.read(
                url,
                onReset: {
                    state.log = UsageLog()
                    state.seen.removeAll()
                },
                onLine: { line, _ in parser.append(line, to: &state.log, seen: &state.seen) })
        } catch {
            // The file vanished or can't be read; it simply adds nothing this time.
            return
        }
    }
}
