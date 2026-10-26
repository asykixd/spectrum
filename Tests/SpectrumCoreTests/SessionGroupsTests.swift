import Foundation
import Testing

@testable import SpectrumCore

private func session(_ id: String, _ kind: AgentSession.Kind, _ activity: AgentActivity)
    -> AgentSession
{
    AgentSession(
        id: id, kind: kind, cwd: nil, activity: activity, startedAt: .distantPast,
        updatedAt: .distantPast)
}

@Test func groupsSessionsIntoCodeChatsAndAFK() {
    let groups = SessionGroups([
        session("waiting", .code, .waitingForUser),
        session("chat-idle", .chat, .idle),
        session("chat-turn", .chat, .waitingForUser),
        session("busy", .code, .usingTool("Bash")),
        session("asleep", .code, .idle),
        session("chat-busy", .chat, .responding),
    ])

    #expect(groups.code.map(\.id) == ["waiting", "busy"])
    #expect(groups.chats.map(\.id) == ["chat-turn", "chat-busy"])
    #expect(groups.afk.map(\.id) == ["chat-idle", "asleep"])
    #expect(!groups.isEmpty)
    #expect(SessionGroups([]).isEmpty)
}
