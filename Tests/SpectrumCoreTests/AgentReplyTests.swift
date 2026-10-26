import Foundation
import Testing

@testable import SpectrumCore

private func session(_ kind: AgentSession.Kind, _ activity: AgentActivity) -> AgentSession {
    AgentSession(
        id: "s", kind: kind, cwd: nil, activity: activity, startedAt: .distantPast,
        updatedAt: .distantPast)
}

@Test func repliesOnlyToIdleCodeSessions() {
    #expect(AgentReply.canReply(to: session(.code, .waitingForUser)))
    #expect(AgentReply.canReply(to: session(.code, .idle)))
    #expect(!AgentReply.canReply(to: session(.code, .usingTool("Bash"))))
    #expect(!AgentReply.canReply(to: session(.chat, .waitingForUser)))
}

@Test func buildsResumeArgumentsWithoutShellInterpolation() {
    let prompt = #"fix it; rm -rf "$HOME""#

    #expect(
        AgentReply.arguments(sessionID: "abc", prompt: prompt) == ["-p", "--resume", "abc", prompt])
    #expect(
        AgentReply.shellScript(home: "/Users/me")
            == #"PATH="/Users/me/.local/bin:/Users/me/.claude/local:/opt/homebrew/bin:/usr/local/bin:$PATH" exec claude "$@""#
    )
}

@Test func emptyPromptsAreRejected() {
    #expect(AgentReply.normalizedPrompt("  \n ") == nil)
    #expect(AgentReply.normalizedPrompt("  go on \n") == "go on")
}

@Test func replySettingDefaultsOnForOldSettings() throws {
    let settings = try JSONDecoder().decode(SpectrumSettings.self, from: Data(#"{}"#.utf8))

    #expect(settings.replyFromPanel)
}
