import Foundation
import Testing

@testable import SpectrumCore

private func assistant(
    _ id: String, at time: String, session: String = "s1", cwd: String = "/code/app",
    model: String = "claude-opus-5-5", input: Int = 0, output: Int = 0, write: Int = 0,
    read: Int = 0
) -> String {
    """
    {"type":"assistant","timestamp":"\(time)","sessionId":"\(session)","cwd":"\(cwd)",\
    "message":{"id":"\(id)","model":"\(model)","usage":{"input_tokens":\(input),\
    "output_tokens":\(output),"cache_creation_input_tokens":\(write),\
    "cache_read_input_tokens":\(read),"cache_creation":{"ephemeral_5m_input_tokens":0,\
    "ephemeral_1h_input_tokens":\(write)}},"content":[]}}
    """
}

private func user(_ text: String, at time: String, session: String = "s1") -> String {
    """
    {"type":"user","timestamp":"\(time)","sessionId":"\(session)","cwd":"/code/app",\
    "message":{"role":"user","content":"\(text)"}}
    """
}

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

@Test func usageIsCountedOncePerMessage() {
    // Claude Code writes one line per content block, each repeating the message's usage.
    let lines = [
        assistant("m1", at: "2026-10-28T10:00:00Z", output: 1_000_000, write: 1_000_000),
        assistant("m1", at: "2026-10-28T10:00:01Z", output: 1_000_000, write: 1_000_000),
    ]
    let log = UsageLog.parse(lines.joined(separator: "\n"))

    #expect(log.entries.count == 1)
    #expect(log.entries[0].tokens.cacheWrite1h == 1_000_000)
    // 20 for output plus 8 for a one-hour cache write.
    #expect(log.entries[0].cost == 28)
}

@Test func costFollowsEachModelsPrices() {
    let opus = UsageLog.Entry(
        messageID: "a", date: .distantPast, sessionID: "s", project: "p",
        model: "claude-opus-5-5",
        tokens: .init(
            input: 1_000_000, output: 0, cacheWrite5m: 0, cacheWrite1h: 1_000_000,
            cacheRead: 1_000_000))
    let sonnet = UsageLog.Entry(
        messageID: "b", date: .distantPast, sessionID: "s", project: "p",
        model: "claude-sonnet-5-5",
        tokens: .init(
            input: 0, output: 1_000_000, cacheWrite5m: 1_000_000, cacheWrite1h: 0,
            cacheRead: 0))

    // 4 input + 8 for a 1-hour write (2x) + 0.20 read.
    #expect(abs(opus.cost - 12.2) < 0.0001)
    // 10 output + 2.50 for a 5-minute write (1.25x).
    #expect(abs(sonnet.cost - 12.5) < 0.0001)
    #expect(ModelPrice.for("claude-opus-4-1-20250805") == ModelPrice.for("claude-opus-4-8"))
}

@Test func reportSumsTodayByProject() {
    let lines = [
        // Yesterday: not part of today's numbers.
        assistant("old", at: "2026-10-27T23:00:00Z", output: 1_000_000),
        user("Add a forecast screen", at: "2026-10-28T09:00:00Z"),
        assistant("m1", at: "2026-10-28T09:00:00Z", output: 100_000),
        assistant("m2", at: "2026-10-28T09:02:00Z", output: 100_000),
        // A long break doesn't count as work.
        assistant("m3", at: "2026-10-28T11:00:00Z", output: 100_000),
        user("Fix the build", at: "2026-10-28T11:00:00Z", session: "s2"),
        assistant(
            "m4", at: "2026-10-28T11:00:00Z", session: "s2", cwd: "/code/api", output: 50_000),
    ]
    let report = BossReport(
        log: UsageLog.parse(lines.joined(separator: "\n")), now: date("2026-10-28T12:00:00Z"),
        calendar: utc)

    #expect(abs(report.todayCost - 7) < 0.0001)
    #expect(report.projects.map(\.name) == ["app", "api"])
    let app = report.projects[0]
    #expect(app.activeTime == 120)
    #expect(app.sessions == 1)
    #expect(app.lastPrompt == "Add a forecast screen")
    #expect(report.projects[1].lastPrompt == "Fix the build")
}

@Test func fiveHourWindowStartsOnTheHourOfItsFirstMessage() {
    let lines = [
        assistant("m1", at: "2026-10-28T06:40:00Z", output: 100_000),
        // More than five hours later: a new window.
        assistant("m2", at: "2026-10-28T12:10:00Z", output: 100_000),
        assistant("m3", at: "2026-10-28T13:00:00Z", output: 100_000),
    ]
    let report = BossReport(
        log: UsageLog.parse(lines.joined(separator: "\n")), now: date("2026-10-28T13:30:00Z"),
        calendar: utc)

    let window = try? #require(report.window)
    #expect(window?.start == date("2026-10-28T12:00:00Z"))
    #expect(window?.end == date("2026-10-28T17:00:00Z"))
    #expect(abs((window?.cost ?? 0) - 4) < 0.0001)
}

@Test func noWindowAfterItExpired() {
    let line = assistant("m1", at: "2026-10-28T06:00:00Z", output: 100)
    let report = BossReport(
        log: UsageLog.parse(line), now: date("2026-10-28T13:30:00Z"), calendar: utc)

    #expect(report.window == nil)
}

@Test func scannerReadsOnlyWhatWasAppended() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let nested = directory.appending(path: "project/session/subagents")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    let main = directory.appending(path: "project/session.jsonl")
    try Data((assistant("m1", at: "2026-10-28T10:00:00Z", output: 10) + "\n").utf8).write(to: main)
    try Data((assistant("a1", at: "2026-10-28T10:01:00Z", output: 10) + "\n").utf8)
        .write(to: nested.appending(path: "agent-1.jsonl"))

    var scanner = UsageScanner(root: directory)
    #expect(scanner.scan(since: .distantPast).entries.count == 2)

    let handle = try FileHandle(forWritingTo: main)
    try handle.seekToEnd()
    // A line still being written has no newline yet and waits for the next scan.
    try handle.write(contentsOf: Data((assistant("m2", at: "2026-10-28T10:02:00Z") + "\n").utf8))
    try handle.write(contentsOf: Data(#"{"type":"assistant","timest"#.utf8))
    try handle.close()

    let log = scanner.scan(since: .distantPast)
    #expect(log.entries.map(\.messageID).sorted() == ["a1", "m1", "m2"])
}
