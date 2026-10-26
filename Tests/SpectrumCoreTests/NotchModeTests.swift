import Testing

@testable import SpectrumCore

@Test func hiddenWhenNothingPlays() {
    let mode = NotchMode.resolve(
        current: .hidden, isPlaying: false, hasTrack: true, isHovering: true, agentsOpen: false)

    #expect(mode == .hidden)
}

@Test func compactWhilePlayingAndExpandsOnHover() {
    let compact = NotchMode.resolve(
        current: .hidden, isPlaying: true, hasTrack: true, isHovering: false, agentsOpen: false)
    let expanded = NotchMode.resolve(
        current: compact, isPlaying: true, hasTrack: true, isHovering: true, agentsOpen: false)

    #expect(compact == .compact)
    #expect(expanded == .expanded)
}

@Test func expandedSurvivesPauseUntilPointerLeaves() {
    let paused = NotchMode.resolve(
        current: .expanded, isPlaying: false, hasTrack: true, isHovering: true, agentsOpen: false)
    let left = NotchMode.resolve(
        current: paused, isPlaying: false, hasTrack: true, isHovering: false, agentsOpen: false)

    #expect(paused == .expanded)
    #expect(left == .hidden)
}

@Test func agentsPanelWinsOverMusic() {
    let mode = NotchMode.resolve(
        current: .compact, isPlaying: true, hasTrack: true, isHovering: true, agentsOpen: true)

    #expect(mode == .agents)
}
