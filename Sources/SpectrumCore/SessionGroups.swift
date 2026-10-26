/// Sessions split the way the office is laid out: desks, meeting room and lounge.
public struct SessionGroups: Equatable, Sendable {
    /// Claude Code sessions that are working or waiting for the user.
    public var code: [AgentSession] = []
    /// Claude app conversations in progress: Claude thinking or answering, or the user's turn.
    public var chats: [AgentSession] = []
    /// Sessions with nothing going on, Claude Code or chat.
    public var afk: [AgentSession] = []

    public init(_ sessions: [AgentSession]) {
        for session in sessions {
            switch (session.kind, session.activity) {
            case (_, .idle), (_, .finished): afk.append(session)
            case (.chat, _): chats.append(session)
            case (.code, _): code.append(session)
            }
        }
    }

    public var isEmpty: Bool { code.isEmpty && chats.isEmpty && afk.isEmpty }
}
