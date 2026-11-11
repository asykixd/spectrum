import Foundation
import os

/// Reads every Claude Code transcript under `~/.claude/projects`, subagents included, and keeps
/// what it read so the next scan only parses lines appended since.
public struct UsageScanner: Sendable {
    private static let signposter = OSSignposter(subsystem: "dev.spectrum", category: "usage")
    private struct FileState: Sendable {
        var reader = JSONLReader()
        var log = UsageLog()
        var seen = Set<String>()
        var modified = Date.distantPast
    }

    private struct Cache: Codable {
        struct File: Codable {
            let checkpoint: JSONLReader.Checkpoint
            let log: UsageLog
            let modified: Date
        }

        let version: Int
        let root: String
        let files: [String: File]
    }

    private let root: URL
    private let cacheURL: URL?
    private var files: [String: FileState] = [:]
    private var restored = false

    public init(root: URL, cacheURL: URL? = nil) {
        self.root = root
        self.cacheURL = cacheURL
    }

    /// The last known totals can be shown while the scanner checks for changed files.
    public mutating func cachedLog(since date: Date) -> UsageLog? {
        restore()
        guard !files.isEmpty else { return nil }
        var total = UsageLog()
        for state in files.values where state.modified >= date { total.append(state.log) }
        return total
    }

    /// Usage from transcripts touched since `date`; older files can't hold newer lines.
    public mutating func scan(since date: Date) -> UsageLog {
        let interval = Self.signposter.beginInterval("Scan transcripts")
        defer { Self.signposter.endInterval("Scan transcripts", interval) }
        restore()
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard
            let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys)
        else { return UsageLog() }
        var total = UsageLog()
        var alive = Set<String>()
        let parser = UsageLog.LineParser()
        var changed = false
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                let modified = values.contentModificationDate, modified >= date
            else { continue }
            let path = url.path
            alive.insert(path)
            var state = files.removeValue(forKey: path) ?? FileState()
            let previous = state.reader.checkpoint
            read(url, into: &state, parser: parser)
            if state.reader.checkpoint != previous || state.modified != modified { changed = true }
            state.modified = modified
            files[path] = state
            total.append(state.log)
        }
        if files.count != alive.count {
            files = files.filter { alive.contains($0.key) }
            changed = true
        }
        if changed { save() }
        return total
    }

    private mutating func restore() {
        guard !restored else { return }
        restored = true
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL),
            let cache = try? PropertyListDecoder().decode(Cache.self, from: data),
            cache.version == 1, cache.root == root.path
        else { return }
        files = cache.files.mapValues { file in
            FileState(
                reader: JSONLReader(checkpoint: file.checkpoint), log: file.log,
                seen: Set(file.log.entries.map(\.messageID)), modified: file.modified)
        }
    }

    private func save() {
        guard let cacheURL else { return }
        let snapshot = files.compactMapValues { state in
            state.reader.checkpoint.map {
                Cache.File(checkpoint: $0, log: state.log, modified: state.modified)
            }
        }
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(Cache(version: 1, root: root.path, files: snapshot))
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try data.write(to: cacheURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
        } catch {
            // The report is still available when the optional cache cannot be written.
            return
        }
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
