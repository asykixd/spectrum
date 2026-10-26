import Testing

@testable import SpectrumCore

/// Feeds `inputs` in order and returns whether each one completed a double tap.
private func run(
    _ inputs: [(DoubleTapDetector.Input, Double)], detector: DoubleTapDetector = .init()
) -> [Bool] {
    var detector = detector
    return inputs.map { detector.handle($0.0, at: $0.1) }
}

@Test func detectsQuickDoubleTap() {
    let results = run([
        (.modifierDown, 0), (.modifierUp, 0.1), (.modifierDown, 0.3), (.modifierUp, 0.35),
    ])

    #expect(results == [false, false, false, true])
}

@Test func ignoresShortcutsLikeCommandC() {
    let results = run([
        (.modifierDown, 0), (.modifierUp, 0.1), (.modifierDown, 0.2), (.other, 0.25),
        (.modifierUp, 0.3),
    ])

    #expect(!results.contains(true))
}

@Test func ignoresSlowTapsAndLongHolds() {
    let results = run([
        (.modifierDown, 0), (.modifierUp, 0.1), (.modifierDown, 1.0), (.modifierUp, 1.1),
        (.modifierDown, 1.2), (.modifierUp, 2.0),
    ])

    #expect(!results.contains(true))
}

@Test func tripleTapFiresOnce() {
    let taps = (0..<3).flatMap { index -> [(DoubleTapDetector.Input, Double)] in
        let start = Double(index) * 0.2
        return [(.modifierDown, start), (.modifierUp, start + 0.05)]
    }

    #expect(run(taps).filter { $0 }.count == 1)
}
