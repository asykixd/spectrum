import Foundation

/// One Claude Code session as seen through its hook events.
public struct AgentSession: Identifiable, Equatable, Sendable {
    public let id: String
    public var cwd: String?
    public var activity: AgentActivity
    public let startedAt: Date
    public var updatedAt: Date

    public init(
        id: String, cwd: String?, activity: AgentActivity, startedAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.cwd = cwd
        self.activity = activity
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }

    public var projectName: String {
        guard let cwd, !cwd.isEmpty else { return "Session \(id.prefix(6))" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// Stable across launches, unlike `hashValue`, so an agent keeps its look in the office.
    public var appearanceSeed: UInt64 {
        id.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
}

/// Live set of agent sessions, folded from hook events.
public struct SessionStore: Equatable, Sendable {
    public private(set) var sessions: [String: AgentSession] = [:]

    public init() {}

    public mutating func apply(_ event: AgentEvent, at date: Date) {
        if event.kind == .sessionEnd {
            sessions[event.sessionID] = nil
            return
        }
        var session =
            sessions[event.sessionID]
            ?? AgentSession(
                id: event.sessionID, cwd: event.cwd, activity: .idle,
                startedAt: date, updatedAt: date)
        session.activity = session.activity.applying(event)
        session.cwd = event.cwd ?? session.cwd
        session.updatedAt = date
        sessions[event.sessionID] = session
    }

    /// Drops sessions that went quiet without a `SessionEnd`, e.g. a closed terminal.
    public mutating func prune(inactiveFor interval: TimeInterval, now: Date) {
        sessions = sessions.filter { now.timeIntervalSince($0.value.updatedAt) < interval }
    }

    /// Sessions waiting for the user first, then working ones, then by start time.
    public var ordered: [AgentSession] {
        sessions.values.sorted { lhs, rhs in
            let left = rank(lhs.activity)
            let right = rank(rhs.activity)
            if left != right { return left < right }
            if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
            return lhs.id < rhs.id
        }
    }

    private func rank(_ activity: AgentActivity) -> Int {
        switch activity {
        case .waitingForUser: 0
        case .thinking, .usingTool: 1
        case .idle, .finished: 2
        }
    }
}
