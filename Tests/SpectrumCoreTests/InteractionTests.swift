import Testing

@testable import SpectrumCore

@Test func hapticsOnlyForInteractiveTransitions() {
    #expect(HapticCue.forTransition(from: .compact, to: .expanded) == .expand)
    #expect(HapticCue.forTransition(from: .hidden, to: .agents) == .expand)
    #expect(HapticCue.forTransition(from: .agents, to: .hidden) == .collapse)
    #expect(HapticCue.forTransition(from: .expanded, to: .compact) == .collapse)
    #expect(HapticCue.forTransition(from: .hidden, to: .compact) == nil)
    #expect(HapticCue.forTransition(from: .compact, to: .hidden) == nil)
    #expect(HapticCue.forTransition(from: .expanded, to: .agents) == .expand)
}

private func swipe(_ deltas: [(Double, Double)], detector: SwipeDetector = .init())
    -> [SwipeDetector.Direction]
{
    var detector = detector
    _ = detector.handle(deltaX: 0, deltaY: 0, phase: .began)
    let results = deltas.compactMap { detector.handle(deltaX: $0.0, deltaY: $0.1, phase: .changed) }
    _ = detector.handle(deltaX: 0, deltaY: 0, phase: .ended)
    return results
}

@Test func swipeLeftFiresOncePerGesture() {
    #expect(swipe([(-20, 1), (-20, 0), (-20, 2), (-40, 0)]) == [.left])
}

@Test func swipeRightGoesBack() {
    #expect(swipe([(30, 0), (30, 0)]) == [.right])
}

@Test func verticalScrollIsIgnored() {
    #expect(
        swipe([
            (5, 40), (5, 40), (5, 40), (5, 40), (5, 40), (5, 40), (5, 40), (5, 40), (5, 40),
            (5, 40), (5, 40),
        ]).isEmpty)
}

@Test func shortSwipeDoesNothing() {
    #expect(swipe([(-20, 0), (-10, 0)]).isEmpty)
}

@Test func panelClosesWhenPointerLeavesAfterVisiting() {
    var dismissal = HoverDismissal()
    let beforeVisit = dismissal.update(isOpen: true, isInside: false)
    let inside = dismissal.update(isOpen: true, isInside: true)
    let left = dismissal.update(isOpen: true, isInside: false)

    #expect(!beforeVisit)
    #expect(!inside)
    #expect(left)
}

@Test func reopenedPanelWaitsForANewVisit() {
    var dismissal = HoverDismissal()
    _ = dismissal.update(isOpen: true, isInside: true)
    _ = dismissal.update(isOpen: false, isInside: false)
    let reopened = dismissal.update(isOpen: true, isInside: false)

    #expect(!reopened)
}
