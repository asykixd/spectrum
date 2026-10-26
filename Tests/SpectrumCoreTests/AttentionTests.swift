import Foundation
import Testing

@testable import SpectrumCore

private let start = Date(timeIntervalSince1970: 0)

private func session(
    _ id: String, _ activity: AgentActivity, kind: AgentSession.Kind = .code
) -> AgentSession {
    AgentSession(
        id: id, kind: kind, cwd: nil, activity: activity, startedAt: start, updatedAt: start)
}

@Test func finishedTaskFlashesBriefly() {
    var tracker = AttentionTracker(doneDuration: 1.6)
    tracker.update([session("a", .thinking)], now: start)
    tracker.update([session("a", .idle)], now: start.addingTimeInterval(10))

    #expect(tracker.signal(at: start.addingTimeInterval(11)) == .done(session("a", .idle)))
    #expect(tracker.signal(at: start.addingTimeInterval(12)) == nil)
}

@Test func chatAnswerCountsAsDone() {
    var tracker = AttentionTracker()
    tracker.update([session("c", .responding, kind: .chat)], now: start)
    tracker.update([session("c", .waitingForUser, kind: .chat)], now: start)

    #expect(tracker.signal(at: start) == .done(session("c", .waitingForUser, kind: .chat)))
}

@Test func permissionRequestPulsesUntilAcknowledged() {
    var tracker = AttentionTracker()
    tracker.update([session("a", .usingTool("Bash"))], now: start)
    tracker.update([session("a", .waitingForUser)], now: start)

    let asking = tracker.signal(at: start.addingTimeInterval(600))
    tracker.acknowledge()
    let afterLooking = tracker.signal(at: start.addingTimeInterval(601))
    tracker.update([session("a", .thinking)], now: start)
    tracker.update([session("a", .waitingForUser)], now: start)
    let askingAgain = tracker.signal(at: start)

    #expect(asking == .needsYou(session("a", .waitingForUser)))
    #expect(afterLooking == nil)
    #expect(askingAgain == .needsYou(session("a", .waitingForUser)))
}

@Test func firstSightingDoesNotFlash() {
    var tracker = AttentionTracker()
    tracker.update([session("a", .idle)], now: start)

    #expect(tracker.signal(at: start) == nil)
}

@Test func idleReminderIsNotARequest() throws {
    let reminder = try AgentEvent.decode(
        Data(
            #"{"session_id":"a","hook_event_name":"Notification","message":"Claude is waiting for your input"}"#
                .utf8))
    let permission = try AgentEvent.decode(
        Data(
            #"{"session_id":"a","hook_event_name":"Notification","message":"Claude needs your permission to use Bash"}"#
                .utf8))

    #expect(AgentActivity.idle.applying(reminder) == .idle)
    #expect(AgentActivity.idle.applying(permission) == .waitingForUser)
}

@Test func attentionOutranksMusicButNotThePanel() {
    let needs = AttentionTracker.Signal.needsYou(session("a", .waitingForUser))

    #expect(
        NotchMode.resolve(
            current: .compact, isPlaying: true, hasTrack: true, isHovering: false,
            agentsOpen: false, signal: needs) == .attention)
    #expect(
        NotchMode.resolve(
            current: .attention, isPlaying: true, hasTrack: true, isHovering: true,
            agentsOpen: true, signal: needs) == .agents)
    #expect(
        NotchMode.resolve(
            current: .hidden, isPlaying: false, hasTrack: false, isHovering: false,
            agentsOpen: false, signal: .done(session("a", .idle))) == .done)
}
