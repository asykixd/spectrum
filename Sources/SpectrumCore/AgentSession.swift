import Foundation

/// One conversation with Claude: a Claude Code session or a chat in the Claude app.
public struct AgentSession: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Claude Code, tracked through hook events.
        case code
        /// A chat in the Claude desktop app, tracked through its accessibility tree.
        case chat
    }

    public let id: String
    public var kind: Kind
    public var title: String?
    public var cwd: String?
    /// Claude Code's JSONL transcript, for showing the conversation.
    public var transcriptPath: String?
    public var activity: AgentActivity
    public let startedAt: Date
    public var updatedAt: Date

    public init(
        id: String, kind: Kind = .code, title: String? = nil, cwd: String?,
        activity: AgentActivity, startedAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.cwd = cwd
        self.activity = activity
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }

    public var projectName: String {
        if let title, !title.isEmpty { return title }
        if kind == .chat { return "Claude chat" }
        guard let cwd, !cwd.isEmpty else { return "Session \(id.prefix(6))" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// Activity in words; a chat waiting on the user reads as a conversation turn.
    public var statusText: String {
        kind == .chat && activity == .waitingForUser ? "Your turn" : activity.summary
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
        session.transcriptPath = event.transcriptPath ?? session.transcriptPath
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
        case .thinking, .usingTool, .responding: 1
        case .idle, .finished: 2
        }
    }
}
