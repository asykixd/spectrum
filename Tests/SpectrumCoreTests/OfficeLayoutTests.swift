import CoreGraphics
import Foundation
import Testing

@testable import SpectrumCore

private func session(_ id: String, _ kind: AgentSession.Kind, _ activity: AgentActivity)
    -> AgentSession
{
    AgentSession(
        id: id, kind: kind, cwd: nil, activity: activity, startedAt: .distantPast,
        updatedAt: .distantPast)
}

@Test func seatsEachGroupInItsZone() {
    let layout = OfficeLayout(sessions: [
        session("busy", .code, .thinking),
        session("chat", .chat, .responding),
        session("idle-chat", .chat, .idle),
    ])

    let zones = Dictionary(uniqueKeysWithValues: layout.placements.map { ($0.session.id, $0.zone) })
    #expect(zones["busy"] == .desk)
    #expect(zones["chat"] == .meeting)
    #expect(zones["idle-chat"] == .sofa)
}

@Test func countsAgentsThatDontFit() {
    let busy = (0..<8).map { session("b\($0)", .code, .thinking) }

    let layout = OfficeLayout(sessions: busy)

    #expect(layout.placements.count == OfficeLayout.deskSlots.count)
    #expect(layout.hiddenCode == 8 - OfficeLayout.deskSlots.count)
}

@Test func hitTestsThroughCanvasCoordinates() {
    let layout = OfficeLayout(sessions: [session("busy", .code, .thinking)])
    // 320 × 156 is exactly 2 points per grid unit with no letterboxing.
    let size = CGSize(width: 320, height: 156)
    let first = OfficeLayout.deskSlots[0]

    let onDesk = OfficeLayout.gridPoint(
        CGPoint(x: (first.x + 5) * 2, y: (first.y - 2) * 2), in: size)
    let onWall = OfficeLayout.gridPoint(CGPoint(x: 10, y: 10), in: size)

    #expect(layout.placement(at: onDesk)?.session.id == "busy")
    #expect(layout.placement(at: onWall) == nil)
}
