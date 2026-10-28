import Foundation

/// Starting a fresh Claude Code session from the panel: it opens in Terminal so the user can
/// follow and steer it like any other session.
public enum NewSession {
    public static func shellCommand(directory: String, prompt: String?) -> String {
        let start = "cd \(shellQuoted(directory)) && claude"
        guard let prompt else { return start }
        return "\(start) \(shellQuoted(prompt))"
    }

    public static func appleScript(command: String) -> String {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
            tell application "Terminal"
                activate
                do script "\(escaped)"
            end tell
            """
    }

    /// Folders the user ran Claude Code in, most recent first, read from the first lines of
    /// each project's newest transcript. Folders that no longer exist are left out.
    public static func recentProjects(in root: URL, limit: Int = 8) -> [String] {
        let fileManager = FileManager.default
        guard
            let folders = try? fileManager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil)
        else { return [] }
        var found: [(path: String, modified: Date)] = []
        for folder in folders {
            guard
                let newest = newestTranscript(in: folder),
                let cwd = firstCwd(in: newest.url),
                fileManager.fileExists(atPath: cwd),
                !found.contains(where: { $0.path == cwd })
            else { continue }
            found.append((cwd, newest.modified))
        }
        return found.sorted { $0.modified > $1.modified }.prefix(limit).map(\.path)
    }

    private static func newestTranscript(in folder: URL) -> (url: URL, modified: Date)? {
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "jsonl" }
            .compactMap { url in
                (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate.map { (url, $0) }
            }
            .max { $0.1 < $1.1 }
    }

    private struct Line: Decodable {
        let cwd: String?
    }

    /// The cwd sits on the first few lines; there's no need to read a whole transcript.
    private static func firstCwd(in url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
        let decoder = JSONDecoder()
        for raw in head.split(separator: UInt8(ascii: "\n")) {
            if let cwd = (try? decoder.decode(Line.self, from: Data(raw)))?.cwd { return cwd }
        }
        return nil
    }

    private static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
