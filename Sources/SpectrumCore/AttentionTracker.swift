import Foundation

/// Decides when the island should call for the user.
///
/// A Claude Code agent asking for permission or an answer blinks the island until the user
/// opens the panel or the agent moves on. A finished task, or a chat Claude just answered, only
/// shows a checkmark for a few seconds.
public struct AttentionTracker: Sendable {
    public enum Signal: Equatable, Sendable {
        case needsYou(AgentSession)
        case done(AgentSession)
    }

    public var doneDuration: TimeInterval

    private var previous: [String: AgentActivity] = [:]
    private var waiting: [AgentSession] = []
    private var acknowledged: Set<String> = []
    private var finished: (session: AgentSession, until: Date)?

    public init(doneDuration: TimeInterval = 3) {
        self.doneDuration = doneDuration
    }

    public mutating func update(_ sessions: [AgentSession], now: Date) {
        for session in sessions {
            if session.activity != .waitingForUser { acknowledged.remove(session.id) }
            guard let old = previous[session.id], old.isWorking else { continue }
            let completed: Bool
            switch (session.kind, session.activity) {
            case (.code, .idle), (.code, .finished), (.chat, .waitingForUser): completed = true
            default: completed = false
            }
            if completed { finished = (session, now.addingTimeInterval(doneDuration)) }
        }
        previous = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.activity) })
        waiting = sessions.filter { $0.kind == .code && $0.activity == .waitingForUser }
    }

    /// The user looked at the panel: stop pulsing for everything waiting right now.
    public mutating func acknowledge() {
        acknowledged.formUnion(waiting.map(\.id))
    }

    public func signal(at now: Date) -> Signal? {
        if let session = waiting.first(where: { !acknowledged.contains($0.id) }) {
            return .needsYou(session)
        }
        if let finished, now < finished.until {
            return .done(finished.session)
        }
        return nil
    }

    /// When the current checkmark should disappear, if one is showing.
    public var doneUntil: Date? { finished?.until }
}
