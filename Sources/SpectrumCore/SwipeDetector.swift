/// Turns a two-finger horizontal trackpad swipe into a single track change.
public struct SwipeDetector: Sendable {
    public enum Phase: Sendable {
        case began
        case changed
        case ended
    }

    public enum Direction: Equatable, Sendable {
        /// Fingers moved left: next track.
        case left
        /// Fingers moved right: previous track.
        case right
    }

    public var threshold: Double

    private var accumulated = 0.0
    private var fired = false

    public init(threshold: Double = 50) {
        self.threshold = threshold
    }

    /// `deltaX` is the physical finger movement, positive to the right.
    public mutating func handle(deltaX: Double, deltaY: Double, phase: Phase) -> Direction? {
        switch phase {
        case .began:
            accumulated = 0
            fired = false
            return nil
        case .ended:
            accumulated = 0
            fired = false
            return nil
        case .changed:
            // Vertical scrolling and the rest of an already recognised swipe are ignored.
            guard !fired, abs(deltaX) > abs(deltaY) else { return nil }
            accumulated += deltaX
            guard abs(accumulated) >= threshold else { return nil }
            fired = true
            return accumulated < 0 ? .left : .right
        }
    }
}
