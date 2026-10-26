import Foundation
import Testing

@testable import SpectrumCore

private let chatURL = URL(string: "https://claude.ai/chat/9abbb3a9-700a#settings")

@Test func snapshotReadsChatIDAndTitle() {
    let snapshot = ClaudeChatSnapshot(
        pageTitle: "эпидемия - Claude", url: chatURL, buttonLabels: ["Копировать"], texts: [])

    #expect(snapshot.chatID == "9abbb3a9-700a")
    #expect(snapshot.title == "эпидемия")
    #expect(!snapshot.isGenerating)
}

@Test func snapshotOutsideAChatHasNoID() {
    let snapshot = ClaudeChatSnapshot(
        pageTitle: "Claude", url: URL(string: "https://claude.ai/new"), buttonLabels: [],
        texts: [])

    #expect(snapshot.chatID == nil)
    #expect(snapshot.title == "")
}

@Test func stopButtonMeansGenerating() {
    let english = ClaudeChatSnapshot(
        pageTitle: nil, url: chatURL, buttonLabels: ["Stop response"], texts: ["Thinking…"])
    let russian = ClaudeChatSnapshot(
        pageTitle: nil, url: chatURL, buttonLabels: ["Остановить ответ"], texts: [])

    #expect(english.isGenerating && english.isThinking)
    #expect(russian.isGenerating && !russian.isThinking)
}

@Test func thinkingTextIgnoredWhenNotGenerating() {
    let snapshot = ClaudeChatSnapshot(
        pageTitle: nil, url: chatURL, buttonLabels: [], texts: ["Thinking about it"])

    #expect(!snapshot.isThinking)
}

private func snapshot(_ chat: String?, generating: Bool = false) -> ClaudeChatSnapshot? {
    chat.map {
        ClaudeChatSnapshot(
            chatID: $0, title: "Chat \($0)", isGenerating: generating, isThinking: false)
    }
}

@Test func trackerTurnsFinishedAnswerIntoUsersTurn() throws {
    var tracker = ClaudeChatTracker()
    let start = Date(timeIntervalSince1970: 0)

    let first = tracker.update(snapshot("a"), at: start)
    let second = tracker.update(snapshot("a", generating: true), at: start.addingTimeInterval(1))
    let third = tracker.update(snapshot("a"), at: start.addingTimeInterval(5))
    let opened = try #require(first.first)
    let answering = try #require(second.first)
    let done = try #require(third.first)

    #expect(opened.activity == .idle)
    #expect(opened.kind == .chat)
    #expect(opened.title == "Chat a")
    #expect(answering.activity == .responding)
    #expect(done.activity == .waitingForUser)
    #expect(done.statusText == "Your turn")
    #expect(done.startedAt == start)
}

@Test func trackerKeepsRecentChatsAfterSwitching() {
    var tracker = ClaudeChatTracker(retention: 15 * 60)
    let start = Date(timeIntervalSince1970: 0)

    _ = tracker.update(snapshot("a", generating: true), at: start)
    let both = tracker.update(snapshot("b"), at: start.addingTimeInterval(10))
    let closedApp = tracker.update(nil, at: start.addingTimeInterval(20))

    #expect(both.map(\.id) == ["claude-chat-b", "claude-chat-a"])
    #expect(both.last?.activity == .waitingForUser)
    #expect(closedApp.count == 2)
}

@Test func trackerForgetsChatsAfterRetention() {
    var tracker = ClaudeChatTracker(retention: 15 * 60)
    let start = Date(timeIntervalSince1970: 0)

    _ = tracker.update(snapshot("old"), at: start)
    _ = tracker.update(snapshot("new"), at: start.addingTimeInterval(10 * 60))
    let later = tracker.update(snapshot("new"), at: start.addingTimeInterval(16 * 60))

    #expect(later.map(\.id) == ["claude-chat-new"])
}

@Test func chatPollingSlowsDownWhenNobodyLooks() {
    #expect(
        ChatPollPolicy.interval(
            panelOpen: true, claudeFrontmost: false, onBattery: true, pauseOnBattery: true) == 1)
    #expect(
        ChatPollPolicy.interval(
            panelOpen: false, claudeFrontmost: true, onBattery: false, pauseOnBattery: true) == 2)
    #expect(
        ChatPollPolicy.interval(
            panelOpen: false, claudeFrontmost: false, onBattery: false, pauseOnBattery: true)
            == 10)
    #expect(
        ChatPollPolicy.interval(
            panelOpen: false, claudeFrontmost: true, onBattery: true, pauseOnBattery: true) == nil)
    #expect(
        ChatPollPolicy.interval(
            panelOpen: false, claudeFrontmost: true, onBattery: true, pauseOnBattery: false) == 2)
}
