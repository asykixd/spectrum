/// Sessions split the way the office is laid out: desks, meeting room and lounge.
public struct SessionGroups: Equatable, Sendable {
    /// Claude Code sessions that are working or waiting for the user.
    public var code: [AgentSession] = []
    /// Conversations in the Claude app.
    public var chats: [AgentSession] = []
    /// Claude Code sessions with nothing to do.
    public var afk: [AgentSession] = []

    public init(_ sessions: [AgentSession]) {
        for session in sessions {
            switch (session.kind, session.activity) {
            case (.chat, _): chats.append(session)
            case (.code, .idle), (.code, .finished): afk.append(session)
            case (.code, _): code.append(session)
            }
        }
    }

    public var isEmpty: Bool { code.isEmpty && chats.isEmpty && afk.isEmpty }
}
