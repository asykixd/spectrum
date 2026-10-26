import Foundation

/// What the Claude desktop app shows right now, read from its accessibility tree.
public struct ClaudeChatSnapshot: Equatable, Sendable {
    public var chatID: String?
    public var title: String?
    public var isGenerating: Bool
    public var isThinking: Bool

    /// Labels of the button that cancels a reply, in the languages the app ships with.
    static let stopLabels = ["stop response", "stop generating", "остановить"]
    /// Header shown while extended thinking streams.
    static let thinkingMarkers = ["thinking", "думает", "размышля"]

    public init(chatID: String?, title: String?, isGenerating: Bool, isThinking: Bool) {
        self.chatID = chatID
        self.title = title
        self.isGenerating = isGenerating
        self.isThinking = isThinking
    }

    /// - Parameters:
    ///   - pageTitle: the claude.ai web area title, e.g. "Trip plan - Claude".
    ///   - url: the claude.ai web area URL; only `/chat/<id>` pages count as a conversation.
    ///   - buttonLabels: descriptions and titles of the buttons on screen.
    ///   - texts: static texts on screen, used to tell thinking from answering.
    public init(pageTitle: String?, url: URL?, buttonLabels: [String], texts: [String]) {
        let components = url?.pathComponents ?? []
        if let index = components.firstIndex(of: "chat"), index + 1 < components.count {
            chatID = components[index + 1]
        } else {
            chatID = nil
        }
        title = pageTitle.map(Self.chatTitle)
        isGenerating = buttonLabels.contains { label in
            let lowered = label.lowercased()
            return Self.stopLabels.contains { lowered.contains($0) }
        }
        isThinking =
            isGenerating
            && texts.contains { text in
                let lowered = text.lowercased()
                return text.count < 40 && Self.thinkingMarkers.contains { lowered.hasPrefix($0) }
            }
    }

    private static func chatTitle(_ pageTitle: String) -> String {
        let suffix = " - Claude"
        let trimmed =
            pageTitle.hasSuffix(suffix) ? String(pageTitle.dropLast(suffix.count)) : pageTitle
        return trimmed == "Claude" ? "" : trimmed
    }
}

/// Turns successive snapshots into conversations between the user and Claude.
///
/// Only the chat on screen can be observed. Chats the user switched away from stay listed with
/// their last known state until `retention` passes without them being open again.
///
/// The app shows no "your turn" signal, so a chat that just finished answering is treated as
/// waiting for the user until Claude starts again.
public struct ClaudeChatTracker: Sendable {
    public var retention: TimeInterval

    private var chats: [String: AgentSession] = [:]
    private var lastSeen: [String: Date] = [:]
    private var openChatID: String?

    public init(retention: TimeInterval = 15 * 60) {
        self.retention = retention
    }

    /// Recent chats, most recently seen first.
    public mutating func update(_ snapshot: ClaudeChatSnapshot?, at date: Date) -> [AgentSession] {
        let chatID = snapshot?.chatID.map { "claude-chat-\($0)" }
        if let previous = openChatID, previous != chatID, var left = chats[previous],
            left.activity.isWorking
        {
            // Claude keeps answering in the background and will be done by the time the user
            // looks again.
            left.activity = .waitingForUser
            left.updatedAt = date
            chats[previous] = left
        }
        openChatID = chatID

        if let snapshot, let id = chatID {
            chats[id] = advance(chats[id], id: id, snapshot: snapshot, at: date)
            lastSeen[id] = date
        }

        for (id, seen) in lastSeen where date.timeIntervalSince(seen) > retention {
            chats[id] = nil
            lastSeen[id] = nil
        }
        return chats.values.sorted {
            (lastSeen[$0.id] ?? .distantPast) > (lastSeen[$1.id] ?? .distantPast)
        }
    }

    private func advance(
        _ existing: AgentSession?, id: String, snapshot: ClaudeChatSnapshot, at date: Date
    ) -> AgentSession {
        var chat =
            existing
            ?? AgentSession(
                id: id, kind: .chat, title: nil, cwd: nil, activity: .idle, startedAt: date,
                updatedAt: date)
        let activity: AgentActivity
        if snapshot.isGenerating {
            activity = snapshot.isThinking ? .thinking : .responding
        } else if chat.activity.isWorking || chat.activity == .waitingForUser {
            activity = .waitingForUser
        } else {
            activity = .idle
        }
        if activity != chat.activity {
            chat.activity = activity
            chat.updatedAt = date
        }
        if let title = snapshot.title, !title.isEmpty {
            chat.title = title
        }
        return chat
    }
}
