import Foundation

/// One coding agent session or a chat in the Claude app.
public struct AgentSession: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A coding agent, tracked through hook events.
        case code
        /// A chat in the Claude desktop app, tracked through its accessibility tree.
        case chat
    }

    public let id: String
    public var kind: Kind
    public let provider: AgentProvider
    public var title: String?
    public var cwd: String?
    /// The agent's JSONL transcript, for showing the conversation.
    public var transcriptPath: String?
    public var terminalTab: TerminalTab?
    public var activity: AgentActivity
    /// A permission request the island can answer, while the hook still waits for it.
    public var permission: PermissionPrompt?
    /// The agent's own plan, when it keeps one.
    public var tasks = TaskList()
    /// Subagents this agent is waiting on right now.
    public var subagents = 0
    /// Files changed since the user's last prompt.
    public var changes = ChangeSummary()
    public let startedAt: Date
    public var updatedAt: Date

    public init(
        id: String, kind: Kind = .code, title: String? = nil, cwd: String?,
        transcriptPath: String? = nil, provider: AgentProvider = .claude, activity: AgentActivity,
        startedAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.provider = provider
        self.title = title
        self.cwd = cwd
        self.transcriptPath = transcriptPath
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

    public mutating func apply(_ event: AgentEvent, at date: Date, permissionID: UUID? = nil) {
        if event.kind == .sessionEnd {
            sessions[event.sessionKey] = nil
            return
        }
        var session =
            sessions[event.sessionKey]
            ?? AgentSession(
                id: event.sessionKey, cwd: event.cwd, provider: event.provider, activity: .idle,
                startedAt: date, updatedAt: date)
        session.activity = session.activity.applying(event)
        // Any later event means the request was settled, by the island or in the terminal.
        session.permission = event.permissionPrompt
        session.permission?.requestID = permissionID
        if let change = event.taskChange { session.tasks.apply(change) }
        session.subagents = Self.subagents(session.subagents, after: event)
        if event.kind == .userPromptSubmit { session.changes = ChangeSummary() }
        if let change = event.fileChange { session.changes.record(change) }
        session.cwd = event.cwd ?? session.cwd
        session.transcriptPath = event.transcriptPath ?? session.transcriptPath
        if event.kind == .sessionStart || event.terminalTab != nil {
            session.terminalTab = event.terminalTab
        }
        session.updatedAt = date
        sessions[event.sessionKey] = session
    }

    private static func subagents(_ count: Int, after event: AgentEvent) -> Int {
        let delegating = event.toolName.map { ToolKind($0) == .delegating } ?? false
        switch event.kind {
        case .preToolUse where delegating: return count + 1
        case .postToolUse where delegating: return max(count - 1, 0)
        // A turn's boundaries reset the count, so a lost finish can't leave a ghost intern.
        case .stop, .interrupt, .userPromptSubmit, .sessionStart: return 0
        default: return count
        }
    }

    /// The island answered the request; the agent carries on without waiting for its next event.
    public mutating func answeredPermission(sessionID: String) {
        guard var session = sessions[sessionID], session.permission != nil else { return }
        session.permission = nil
        session.activity = .thinking
        sessions[sessionID] = session
    }

    /// The island can't answer this request (disabled or timed out): Claude Code asks in the
    /// terminal instead, and the agent keeps waiting there.
    public mutating func expirePermission(sessionID: String) {
        sessions[sessionID]?.permission = nil
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
