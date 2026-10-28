import Foundation
import Testing

@testable import SpectrumCore

private func event(_ kind: String, tool: String? = nil) throws -> AgentEvent {
    var json = ["session_id": "s", "hook_event_name": kind]
    json["tool_name"] = tool
    return try AgentEvent.decode(JSONSerialization.data(withJSONObject: json))
}

@Test func toolsMapToWhatTheAgentDoesAtItsDesk() {
    #expect(ToolKind("Read") == .reading)
    #expect(ToolKind("Grep") == .reading)
    #expect(ToolKind("Edit") == .writing)
    #expect(ToolKind("Write") == .writing)
    #expect(ToolKind("Bash") == .terminal)
    #expect(ToolKind("WebSearch") == .browsing)
    #expect(ToolKind("WebFetch") == .browsing)
    #expect(ToolKind("Task") == .delegating)
    #expect(ToolKind("Agent") == .delegating)
    #expect(ToolKind("mcp__github__create_issue") == .writing)
}

@Test func subagentsComeAndGoWithTheirTaskCalls() throws {
    var store = SessionStore()
    try store.apply(event("PreToolUse", tool: "Task"), at: .distantPast)
    try store.apply(event("PreToolUse", tool: "Agent"), at: .distantPast)
    #expect(store.sessions["s"]?.subagents == 2)

    try store.apply(event("PostToolUse", tool: "Task"), at: .distantPast)
    #expect(store.sessions["s"]?.subagents == 1)

    // A new turn starts fresh even if a finish went missing.
    try store.apply(event("Stop"), at: .distantPast)
    #expect(store.sessions["s"]?.subagents == 0)
    try store.apply(event("PostToolUse", tool: "Task"), at: .distantPast)
    #expect(store.sessions["s"]?.subagents == 0)
}
