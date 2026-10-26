import Foundation

/// Sessions the user removed from the list.
///
/// A removed session comes back as soon as it does something new, so dismissing an idle agent
/// never hides one that later needs the user.
public struct Dismissals: Equatable, Sendable {
    private var dismissedAt: [String: Date] = [:]

    public init() {}

    public mutating func dismiss(_ session: AgentSession) {
        dismissedAt[session.id] = session.updatedAt
    }

    public mutating func visible(_ sessions: [AgentSession]) -> [AgentSession] {
        let ids = Set(sessions.map(\.id))
        // Forget sessions that ended so the table doesn't grow forever.
        dismissedAt = dismissedAt.filter { ids.contains($0.key) }
        return sessions.filter { session in
            guard let date = dismissedAt[session.id] else { return true }
            return session.updatedAt > date
        }
    }
}
