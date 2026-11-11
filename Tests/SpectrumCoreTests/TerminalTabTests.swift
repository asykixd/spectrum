import Foundation
import Testing

@testable import SpectrumCore

@Test func hookKeepsTerminalTabsSeparateForSessionsInTheSameProject() throws {
    let claudeTab = try #require(TerminalTab(tty: "/dev/ttys001", sessionLeader: 101))
    let codexTab = try #require(TerminalTab(tty: "/dev/ttys002", sessionLeader: 102))
    let start = Data(
        #"{"session_id":"s1","hook_event_name":"SessionStart","cwd":"/tmp/project"}"#.utf8)
    let claude = try AgentEvent.decode(
        AgentEvent.forwardedPayload(start, from: .claude, terminalTab: claudeTab))
    let codex = try AgentEvent.decode(
        AgentEvent.forwardedPayload(start, from: .codex, terminalTab: codexTab))
    let tool = try AgentEvent.decode(
        Data(#"{"session_id":"s1","hook_event_name":"PreToolUse"}"#.utf8))
    var store = SessionStore()
    for event in [claude, codex, tool] { store.apply(event, at: .distantPast) }

    #expect(store.sessions[claude.sessionKey]?.terminalTab == claudeTab)
    #expect(store.sessions[codex.sessionKey]?.terminalTab == codexTab)

    store.apply(try AgentEvent.decode(start), at: .distantPast)
    #expect(store.sessions[claude.sessionKey]?.terminalTab == nil)
    #expect(store.sessions[codex.sessionKey]?.terminalTab == codexTab)
}

@Test func terminalFocusTargetsTheDeviceWithoutRunningACommand() throws {
    let tab = try #require(TerminalTab(tty: "/dev/ttys009", sessionLeader: Int32.max))
    #expect(tab.focusScript.contains(#"if tty of candidateTab is "/dev/ttys009" then"#))
    #expect(tab.focusScript.contains("set selected of candidateTab to true"))
    #expect(!tab.focusScript.contains("do script"))
    #expect(!tab.isLive)
}

@Test func untrustedOrMissingTerminalMetadataDoesNotStopHookDelivery() throws {
    let malformed = Data(
        #"{"session_id":"s1","hook_event_name":"Stop","spectrum_terminal_tty":"/dev/ttys001\"","spectrum_terminal_leader":101}"#
            .utf8)

    #expect(try AgentEvent.decode(malformed).terminalTab == nil)
    #expect(TerminalTab(tty: "/dev/ttys001", sessionLeader: -1) == nil)
    #expect(TerminalTab.capture(environment: ["TERM_PROGRAM": "iTerm.app"]) == nil)
    #expect(
        TerminalTab.capture(environment: ["TERM_PROGRAM": "Apple_Terminal", "TMUX": "1"]) == nil)
}
