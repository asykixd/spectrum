import Foundation

/// Reads every Claude Code transcript under `~/.claude/projects`, subagents included, and keeps
/// what it read so the next scan only parses lines appended since.
public struct UsageScanner: Sendable {
    private struct FileState: Sendable {
        var offset: UInt64
        var log: UsageLog
    }

    private let root: URL
    private var files: [String: FileState] = [:]

    public init(root: URL) {
        self.root = root
    }

    /// Usage from transcripts touched since `date`; older files can't hold newer lines.
    public mutating func scan(since date: Date) -> UsageLog {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard
            let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys)
        else { return UsageLog() }
        var total = UsageLog()
        var alive = Set<String>()
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                let modified = values.contentModificationDate, modified >= date,
                let size = values.fileSize
            else { continue }
            let path = url.path
            alive.insert(path)
            var state = files[path] ?? FileState(offset: 0, log: UsageLog())
            // A rewritten (shorter) file starts over.
            if UInt64(size) < state.offset { state = FileState(offset: 0, log: UsageLog()) }
            if UInt64(size) > state.offset { read(url, into: &state) }
            files[path] = state
            total.append(state.log)
        }
        files = files.filter { alive.contains($0.key) }
        return total
    }

    private func read(_ url: URL, into state: inout FileState) {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: state.offset)
            let data = try handle.readToEnd() ?? Data()
            // Stop at the last complete line; the rest is still being written.
            guard let end = data.lastIndex(of: UInt8(ascii: "\n")) else { return }
            let complete = data[data.startIndex...end]
            state.log.append(UsageLog.parse(String(decoding: complete, as: UTF8.self)))
            state.offset += UInt64(complete.count)
        } catch {
            // The file vanished or can't be read; it simply adds nothing this time.
            return
        }
    }
}
