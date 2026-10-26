import Foundation
import Testing

@testable import SpectrumCore

private func event(_ kind: String, session: String = "s1", tool: String? = nil) throws
    -> AgentEvent
{
    var json: [String: String] = [
        "session_id": session, "hook_event_name": kind, "cwd": "/Users/me/code/\(session)-app",
    ]
    json["tool_name"] = tool
    return try AgentEvent.decode(JSONSerialization.data(withJSONObject: json))
}

@Test func sessionAppearsAndTracksActivity() throws {
    var store = SessionStore()
    let start = Date(timeIntervalSince1970: 100)

    try store.apply(event("SessionStart"), at: start)
    try store.apply(event("PreToolUse", tool: "Bash"), at: start.addingTimeInterval(5))

    let session = try #require(store.sessions["s1"])
    #expect(session.activity == .usingTool("Bash"))
    #expect(session.projectName == "s1-app")
    #expect(session.startedAt == start)
    #expect(session.updatedAt == start.addingTimeInterval(5))
}

@Test func sessionEndRemovesSession() throws {
    var store = SessionStore()
    try store.apply(event("SessionStart"), at: Date())
    try store.apply(event("SessionEnd"), at: Date())

    #expect(store.sessions.isEmpty)
}

@Test func orderedPutsWaitingSessionsFirst() throws {
    var store = SessionStore()
    let now = Date(timeIntervalSince1970: 0)
    try store.apply(event("SessionStart", session: "idle"), at: now)
    try store.apply(event("UserPromptSubmit", session: "busy"), at: now.addingTimeInterval(1))
    try store.apply(event("Notification", session: "waiting"), at: now.addingTimeInterval(2))

    #expect(store.ordered.map(\.id) == ["waiting", "busy", "idle"])
}

@Test func pruneDropsQuietSessions() throws {
    var store = SessionStore()
    let now = Date(timeIntervalSince1970: 1000)
    try store.apply(event("Stop", session: "old"), at: now.addingTimeInterval(-3600))
    try store.apply(event("Stop", session: "fresh"), at: now.addingTimeInterval(-10))

    store.prune(inactiveFor: 1800, now: now)

    #expect(Array(store.sessions.keys) == ["fresh"])
}

@Test func appearanceSeedIsStable() {
    let session = AgentSession(
        id: "abc", cwd: nil, activity: .idle, startedAt: .distantPast, updatedAt: .distantPast)

    #expect(session.appearanceSeed == 0xe71f_a219_0541_574b)
    #expect(session.projectName == "Session abc")
}

@Test func activitySummaries() {
    #expect(AgentActivity.usingTool("Edit").summary == "Running Edit")
    #expect(AgentActivity.waitingForUser.summary == "Waiting for you")
    #expect(AgentActivity.thinking.isWorking)
    #expect(!AgentActivity.idle.isWorking)
}
