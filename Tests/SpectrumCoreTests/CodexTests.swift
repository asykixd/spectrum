import Foundation
import Testing

@testable import SpectrumCore

@Test func installsAndRemovesCodexHooksWithoutChangingUserHooks() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: "hooks.json")
    let original = Data(
        #"{"description":"user hooks","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo user"}]}]}}"#
            .utf8)
    try original.write(to: url)

    let executable = "/Applications/Spectrum's App"
    for _ in 0..<2 {
        try HookInstaller.install(executablePath: executable, settingsURL: url, provider: .codex)
    }

    let settings = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let hooks = try #require(settings["hooks"] as? [String: [[String: Any]]])
    #expect(
        Set(hooks.keys) == [
            "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest",
            "Stop", "Interrupt", "SessionEnd",
        ])
    #expect(hooks["Stop"]?.count == 2)
    let interrupt = try #require((hooks["Interrupt"]?.first?["hooks"] as? [[String: Any]])?.first)
    #expect(interrupt["timeout"] as? Int == 3)
    #expect(
        interrupt["command"] as? String
            == #"'/Applications/Spectrum'\''s App' hook codex # spectrum"#)
    #expect(HookInstaller.isInstalled(settingsURL: url))
    #expect(
        !HookInstaller.needsUpdate(settingsURL: url, executablePath: executable, provider: .codex))
    #expect(try Data(contentsOf: url.appendingPathExtension("spectrum-backup")) == original)

    try HookInstaller.uninstall(settingsURL: url)
    let restored = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    let expected = try JSONSerialization.jsonObject(with: original)
    #expect(
        try JSONSerialization.data(withJSONObject: restored, options: .sortedKeys)
            == JSONSerialization.data(withJSONObject: expected, options: .sortedKeys))
}

@Test func codexEventsTrackActivityAndPermissionsSeparatelyFromClaude() throws {
    func event(_ name: String, provider: AgentProvider = .codex) throws -> AgentEvent {
        let input = Data(
            """
            {"hook_event_name":"\(name)","session_id":"same-id","cwd":"/tmp/demo",
             "transcript_path":"/tmp/rollout.jsonl","tool_name":"Bash","tool_input":{"command":"swift test"}}
            """.utf8)
        return try AgentEvent.decode(AgentEvent.forwardedPayload(input, from: provider))
    }

    let now = Date()
    var store = SessionStore()
    let start = try event("SessionStart")
    store.apply(start, at: now)
    store.apply(try event("SessionStart", provider: .claude), at: now)
    let id = start.sessionKey
    #expect(store.sessions.count == 2)
    #expect(store.sessions[id]?.provider == .codex)
    #expect(store.sessions[id]?.transcriptPath == "/tmp/rollout.jsonl")
    #expect(try !AgentReply.canReply(to: #require(store.sessions[id])))

    store.apply(try event("UserPromptSubmit"), at: now)
    #expect(store.sessions[id]?.activity == .thinking)
    store.apply(try event("PreToolUse"), at: now)
    #expect(store.sessions[id]?.activity == .usingTool("Bash"))
    store.apply(try event("PermissionRequest"), at: now)
    #expect(store.sessions[id]?.activity == .waitingForUser)
    #expect(store.sessions[id]?.permission == PermissionPrompt(tool: "Bash", detail: "swift test"))
    store.answeredPermission(sessionID: id)
    #expect(store.sessions[id]?.activity == .thinking)
    store.apply(try event("Interrupt"), at: now)
    #expect(store.sessions[id]?.activity == .idle)
    store.apply(try event("SessionEnd"), at: now)
    #expect(store.ordered.map(\.provider) == [.claude])
}

@Test func readsCodexMessagesAndToolCalls() {
    let input = #"""
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>"}]}}
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Run the tests"}]}}
        {"type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\"command\":\"swift test\"}"}}
        {"type":"response_item","payload":{"type":"custom_tool_call","name":"apply_patch","input":"patch"}}
        {"type":"response_item","payload":{"type":"function_call_output","output":"tool output"}}
        {"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Tests passed."}]}}
        {"type":"response_item","payload":
        """#
    let messages = Transcript.parse(input, provider: .codex)
    #expect(messages.map(\.role) == [.user, .tool, .tool, .assistant])
    #expect(
        messages.map(\.text) == [
            "Run the tests", "exec_command: swift test", "apply_patch", "Tests passed.",
        ])
}
