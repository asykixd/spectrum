import Foundation
import Testing

@testable import SpectrumCore

private func decode(_ json: String) throws -> AgentEvent {
    try AgentEvent.decode(Data(json.utf8))
}

private let bashRequest = #"""
    {"session_id":"s1","hook_event_name":"PermissionRequest","cwd":"/code/app","tool_name":"Bash",
     "tool_input":{"command":"rm -rf build","description":"Remove build","timeout":5}}
    """#

@Test func permissionRequestCarriesWhatTheAgentAsks() throws {
    let event = try decode(bashRequest)

    #expect(event.kind == .permissionRequest)
    #expect(event.permissionPrompt == PermissionPrompt(tool: "Bash", detail: "rm -rf build"))
    #expect(AgentActivity.thinking.applying(event) == .waitingForUser)
}

@Test func permissionDetailFallsBackToPathsAndUrls() throws {
    let edit = try decode(
        #"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"Edit","tool_input":{"file_path":"/a/b.swift","old_string":"x"}}"#
    )
    let fetch = try decode(
        #"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"WebFetch","tool_input":{"url":"https://x.dev","prompt":"read"}}"#
    )
    let bare = try decode(
        #"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"mcp__x"}"#)

    #expect(edit.permissionPrompt?.detail == "/a/b.swift")
    #expect(fetch.permissionPrompt?.detail == "https://x.dev")
    #expect(bare.permissionPrompt == PermissionPrompt(tool: "mcp__x", detail: nil))
}

@Test func storeKeepsThePromptUntilTheAgentMovesOn() throws {
    var store = SessionStore()
    let start = Date(timeIntervalSince1970: 0)
    try store.apply(decode(bashRequest), at: start)

    #expect(store.sessions["s1"]?.permission?.detail == "rm -rf build")
    #expect(store.sessions["s1"]?.activity == .waitingForUser)

    try store.apply(
        decode(#"{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Bash"}"#),
        at: start)
    #expect(store.sessions["s1"]?.permission == nil)
}

@Test func answeringClearsThePromptAndResumesWork() throws {
    var store = SessionStore()
    try store.apply(decode(bashRequest), at: Date(timeIntervalSince1970: 0))

    store.answeredPermission(sessionID: "s1")

    #expect(store.sessions["s1"]?.permission == nil)
    #expect(store.sessions["s1"]?.activity == .thinking)
}

@Test func decisionIsTheJsonClaudeCodeExpects() throws {
    let allow = try JSONSerialization.jsonObject(with: PermissionDecision.allow.hookOutput)
    let deny = try JSONSerialization.jsonObject(with: PermissionDecision.deny.hookOutput)

    let allowOutput = (allow as? [String: Any])?["hookSpecificOutput"] as? [String: Any]
    #expect(allowOutput?["hookEventName"] as? String == "PermissionRequest")
    #expect((allowOutput?["decision"] as? [String: Any])?["behavior"] as? String == "allow")
    let denyOutput = (deny as? [String: Any])?["hookSpecificOutput"] as? [String: Any]
    let denyDecision = denyOutput?["decision"] as? [String: Any]
    #expect(denyDecision?["behavior"] as? String == "deny")
    #expect(denyDecision?["message"] as? String != nil)
}

@Test func hoveringASignalWithAPromptOpensIt() {
    var session = AgentSession(
        id: "a", cwd: nil, activity: .waitingForUser, startedAt: .distantPast,
        updatedAt: .distantPast)
    session.permission = PermissionPrompt(tool: "Bash", detail: "ls")
    let asking = AttentionTracker.Signal.needsYou(session)

    #expect(
        NotchMode.resolve(
            current: .attention, isPlaying: false, hasTrack: false, isHovering: true,
            agentsOpen: false, signal: asking) == .permission)
    #expect(
        NotchMode.resolve(
            current: .compact, isPlaying: true, hasTrack: true, isHovering: true,
            agentsOpen: false, signal: asking) == .permission)
    #expect(
        NotchMode.resolve(
            current: .hidden, isPlaying: false, hasTrack: false, isHovering: true,
            agentsOpen: false, signal: asking) == .attention)
    #expect(
        NotchMode.resolve(
            current: .permission, isPlaying: false, hasTrack: false, isHovering: true,
            agentsOpen: true, signal: asking) == .agents)
}

@Test func alwaysAllowEchoesOnlyAnExactLocalBashSuggestion() throws {
    let input = Data(
        #"{"session_id":"abc","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"swift test"},"permission_suggestions":[{"type":"addRules","behavior":"allow","destination":"localSettings","rules":[{"toolName":"Bash","ruleContent":"swift test"}]}]}"#
            .utf8)
    let event = try AgentEvent.decode(input)
    let rule = try #require(event.permissionPrompt?.projectRule)
    let output = try #require(
        String(data: PermissionDecision.alwaysAllow(rule).hookOutput, encoding: .utf8))
    #expect(output.contains(#""destination":"localSettings""#))
    #expect(output.contains(#""ruleContent":"swift test""#))
    #expect(output.contains(#""behavior":"allow""#))

    for replacement in ["swift *", "swift", "swift test && git push"] {
        let invalid = String(decoding: input, as: UTF8.self)
            .replacingOccurrences(
                of: #""ruleContent":"swift test""#, with: #""ruleContent":"\#(replacement)""#)
        #expect(try AgentEvent.decode(Data(invalid.utf8)).permissionPrompt?.projectRule == nil)
    }
    let codex = try AgentEvent.decode(AgentEvent.forwardedPayload(input, from: .codex))
    #expect(codex.permissionPrompt?.projectRule == nil)
    #expect(ProjectPermissionRule(tool: "Bash", command: "swift *") == nil)
}

@Test func consecutivePermissionsKeepDistinctRequestIDs() throws {
    let input = Data(
        #"{"session_id":"abc","hook_event_name":"PermissionRequest","tool_name":"Bash"}"#.utf8)
    let event = try AgentEvent.decode(input)
    let originalID = UUID()
    let replacementID = UUID()
    var store = SessionStore()
    store.apply(event, at: .distantPast, permissionID: originalID)
    let original = try #require(store.sessions["abc"]?.permission)
    store.apply(event, at: .now, permissionID: replacementID)
    #expect(original.requestID == originalID)
    #expect(store.sessions["abc"]?.permission?.requestID == replacementID)
}
