import Foundation
import Testing

@testable import SpectrumCore

@Test func restoredUsageCursorCompletesAPartialRecordWithoutDuplicatingTheCache() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appending(path: "projects")
    let cache = directory.appending(path: "cache/usage.plist")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let transcript = root.appending(path: "session.jsonl")
    let first = usageLine("first")
    let second = usageLine("second")
    let split = second.index(second.startIndex, offsetBy: 20)
    try Data((first + second[..<split]).utf8).write(to: transcript)

    var original = UsageScanner(root: root, cacheURL: cache)
    #expect(original.scan(since: .distantPast).entries.map(\.messageID) == ["first"])
    var reopened = UsageScanner(root: root, cacheURL: cache)
    #expect(reopened.cachedLog(since: .distantPast)?.entries.map(\.messageID) == ["first"])

    let handle = try FileHandle(forWritingTo: transcript)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(second[split...].utf8))
    #expect(reopened.scan(since: .distantPast).entries.map(\.messageID) == ["first", "second"])
}

@Test func usageCacheIgnoresCorruptDataAndReplacedTranscripts() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appending(path: "projects")
    let cache = directory.appending(path: "usage.plist")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("broken cache".utf8).write(to: cache)
    let transcript = root.appending(path: "session.jsonl")
    try Data(usageLine("first").utf8).write(to: transcript)

    var scanner = UsageScanner(root: root, cacheURL: cache)
    #expect(scanner.cachedLog(since: .distantPast) == nil)
    #expect(scanner.scan(since: .distantPast).entries.map(\.messageID) == ["first"])
    try Data(usageLine("other").utf8).write(to: transcript, options: .atomic)

    var reopened = UsageScanner(root: root, cacheURL: cache)
    #expect(reopened.scan(since: .distantPast).entries.map(\.messageID) == ["other"])
    #expect(reopened.cachedLog(since: .distantFuture)?.entries.isEmpty == true)
    let mode =
        try FileManager.default.attributesOfItem(atPath: cache.path)[.posixPermissions] as? Int
    #expect(mode == 0o600)
}

private func usageLine(_ id: String) -> String {
    """
    {"type":"assistant","timestamp":"2026-10-28T10:00:00Z","sessionId":"s1","message":{"id":"\(id)","model":"claude-sonnet-4-6","usage":{"input_tokens":1}}}

    """
}
