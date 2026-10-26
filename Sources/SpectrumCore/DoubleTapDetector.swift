import Foundation

/// Recognises a double tap of a lone modifier key, e.g. ⌘ ⌘.
///
/// A tap counts only if the key is released quickly and nothing else was pressed meanwhile,
/// so ordinary shortcuts like ⌘C never open the panel.
public struct DoubleTapDetector: Sendable {
    public enum Input: Sendable {
        case modifierDown
        case modifierUp
        /// Any other key or modifier.
        case other
    }

    public var maxTapDuration: TimeInterval
    public var maxGap: TimeInterval

    private var downAt: TimeInterval?
    private var lastTapAt: TimeInterval?
    private var interrupted = false

    public init(maxTapDuration: TimeInterval = 0.3, maxGap: TimeInterval = 0.4) {
        self.maxTapDuration = maxTapDuration
        self.maxGap = maxGap
    }

    /// Returns true when `input` completes a double tap.
    public mutating func handle(_ input: Input, at time: TimeInterval) -> Bool {
        switch input {
        case .modifierDown:
            downAt = time
            interrupted = false
            return false
        case .other:
            interrupted = true
            lastTapAt = nil
            return false
        case .modifierUp:
            guard let down = downAt else { return false }
            downAt = nil
            guard !interrupted, time - down <= maxTapDuration else {
                lastTapAt = nil
                return false
            }
            if let last = lastTapAt, down - last <= maxGap {
                lastTapAt = nil
                return true
            }
            lastTapAt = time
            return false
        }
    }
}
