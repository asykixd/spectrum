import Foundation
import Testing

@testable import SpectrumCore

@Test func cursorEventsUseConversationIdentityAndWorkspaceRoot() throws {
    let input = Data(
        #"{"conversation_id":"same","generation_id":"turn","hook_event_name":"beforeSubmitPrompt","workspace_roots":["/tmp/project"],"user_email":"test@example.org","transcript_path":"/tmp/cursor-history.jsonl"}"#
            .utf8)
    let forwarded = try AgentEvent.forwardedPayload(input, from: .cursor)
    let event = try AgentEvent.decode(forwarded)
    #expect(event.provider == .cursor)
    #expect(event.kind == .userPromptSubmit)
    #expect(event.sessionKey == "cursor:same")
    #expect(event.cwd == "/tmp/project")
    #expect(event.transcriptPath == nil)
    #expect(!String(decoding: forwarded, as: UTF8.self).contains("test@example.org"))

    let copilot = try AgentEvent.decode(
        AgentEvent.forwardedPayload(
            Data(
                #"{"session_id":"same","hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"/tmp/project"}"#
                    .utf8),
            from: .copilot))
    #expect(copilot.sessionKey == "copilot:same")
    #expect(copilot.kind == .preToolUse)
}

@Test func extraProviderHookFilesPreserveExistingCommands() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let cursor = directory.appending(path: "cursor.json")
    try Data(#"{"version":1,"hooks":{"postToolUse":[{"command":"personal-hook"}]}}"#.utf8)
        .write(to: cursor)
    try HookInstaller.install(
        executablePath: "/Applications/Spectrum.app/hook", settingsURL: cursor, provider: .cursor)
    #expect(HookInstaller.isInstalled(settingsURL: cursor, provider: .cursor))
    #expect(
        !HookInstaller.needsUpdate(
            settingsURL: cursor, executablePath: "/Applications/Spectrum.app/hook",
            provider: .cursor))
    let output = try String(contentsOf: cursor, encoding: .utf8)
    #expect(output.contains("personal-hook"))
    #expect(output.contains("hook cursor"))
    #expect(!output.contains("preToolUse"))
    try HookInstaller.uninstall(settingsURL: cursor, provider: .cursor)
    #expect(!HookInstaller.isInstalled(settingsURL: cursor, provider: .cursor))
    #expect(try String(contentsOf: cursor, encoding: .utf8).contains("personal-hook"))

    let copilot = directory.appending(path: "copilot.json")
    try HookInstaller.install(
        executablePath: "/Applications/Spectrum.app/hook", settingsURL: copilot, provider: .copilot)
    let config = try String(contentsOf: copilot, encoding: .utf8)
    #expect(config.contains("PreToolUse"))
    #expect(config.contains("hook copilot || true"))
    #expect(config.contains("timeoutSec"))
    try HookInstaller.uninstall(settingsURL: copilot, provider: .copilot)
    #expect(!HookInstaller.isInstalled(settingsURL: copilot, provider: .copilot))
}
