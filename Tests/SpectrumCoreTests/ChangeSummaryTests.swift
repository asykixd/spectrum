import Foundation
import Testing

@testable import SpectrumCore

private func event(_ kind: String, tool: String? = nil, input: [String: Any]? = nil) throws
    -> AgentEvent
{
    var json: [String: Any] = ["session_id": "s", "hook_event_name": kind]
    json["tool_name"] = tool
    json["tool_input"] = input
    return try AgentEvent.decode(JSONSerialization.data(withJSONObject: json))
}

@Test func editCountsOnlyTheLinesThatChanged() throws {
    let change = try event(
        "PostToolUse", tool: "Edit",
        input: [
            "file_path": "/a/View.swift",
            "old_string": "struct A {\n    let x = 1\n}",
            "new_string": "struct A {\n    let x = 2\n    let y = 3\n}",
        ]
    ).fileChange

    #expect(change == FileChange(path: "/a/View.swift", added: 2, removed: 1))
}

@Test func writeAndMultiEditAreCounted() throws {
    let write = try event(
        "PostToolUse", tool: "Write", input: ["file_path": "/a/new.swift", "content": "a\nb\nc\n"]
    ).fileChange
    let multi = try event(
        "PostToolUse", tool: "MultiEdit",
        input: [
            "file_path": "/a/b.swift",
            "edits": [
                ["old_string": "x", "new_string": "y"], ["old_string": "p\nq", "new_string": ""],
            ],
        ]
    ).fileChange

    #expect(write == FileChange(path: "/a/new.swift", added: 3, removed: 0))
    #expect(multi == FileChange(path: "/a/b.swift", added: 1, removed: 3))
    #expect(
        try event("PreToolUse", tool: "Write", input: ["file_path": "/x", "content": "a"])
            .fileChange == nil)
}

@Test func summaryCoversOneTurn() throws {
    var store = SessionStore()
    try store.apply(event("UserPromptSubmit"), at: .distantPast)
    try store.apply(
        event("PostToolUse", tool: "Write", input: ["file_path": "/a", "content": "1\n2"]),
        at: .distantPast)
    try store.apply(
        event(
            "PostToolUse", tool: "Edit",
            input: ["file_path": "/a", "old_string": "1", "new_string": "one"]), at: .distantPast)
    try store.apply(
        event("PostToolUse", tool: "Write", input: ["file_path": "/b", "content": "x"]),
        at: .distantPast)
    try store.apply(event("Stop"), at: .distantPast)

    let summary = try #require(store.sessions["s"]?.changes)
    #expect(summary.files == 2)
    #expect(summary.added == 4)
    #expect(summary.removed == 1)

    try store.apply(event("UserPromptSubmit"), at: .distantPast)
    #expect(store.sessions["s"]?.changes.isEmpty == true)
}
