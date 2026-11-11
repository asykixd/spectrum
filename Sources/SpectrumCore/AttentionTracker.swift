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
    public var remindAfter: TimeInterval?

    private struct WaitKey: Hashable, Sendable {
        let session: String
        let request: UUID?

        init(_ session: AgentSession) {
            self.session = session.id
            request = session.permission?.requestID
        }
    }

    private struct Acknowledgement: Sendable {
        let date: Date
        var reminded = false
    }

    private var previous: [String: AgentActivity] = [:]
    private var waiting: [AgentSession] = []
    private var acknowledged: [WaitKey: Acknowledgement] = [:]
    private var finished: (session: AgentSession, until: Date)?

    public init(doneDuration: TimeInterval = 3, remindAfter: TimeInterval? = nil) {
        self.doneDuration = doneDuration
        self.remindAfter = remindAfter
    }

    public mutating func update(_ sessions: [AgentSession], now: Date) {
        for session in sessions {
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
        let visible = Set(waiting.map(WaitKey.init))
        acknowledged = acknowledged.filter { visible.contains($0.key) }
    }

    /// The user looked at the panel: stop pulsing for everything waiting right now.
    public mutating func acknowledge(now: Date = Date(), includeReminders: Bool = true) {
        for session in waiting {
            let key = WaitKey(session)
            if acknowledged[key] == nil {
                acknowledged[key] = Acknowledgement(date: now)
            } else if includeReminders, let deadline = reminder(for: key), now >= deadline {
                acknowledged[key]?.reminded = true
            }
        }
    }

    public func nextReminder(after now: Date) -> Date? {
        waiting.compactMap { reminder(for: WaitKey($0)) }.filter { $0 > now }.min()
    }

    private func reminder(for key: WaitKey) -> Date? {
        guard let remindAfter, let seen = acknowledged[key], !seen.reminded else { return nil }
        return seen.date.addingTimeInterval(remindAfter)
    }

    public func signal(at now: Date) -> Signal? {
        let needsAttention = waiting.filter { session in
            let key = WaitKey(session)
            return acknowledged[key] == nil || reminder(for: key).map { now >= $0 } == true
        }
        if let session = needsAttention.first(where: { $0.permission != nil })
            ?? needsAttention.first
        {
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
