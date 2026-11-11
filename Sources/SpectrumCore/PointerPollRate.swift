import CoreGraphics
import Foundation

public enum PointerPollRate: Equatable, Sendable {
    case near
    case far

    public var interval: TimeInterval { self == .near ? 0.05 : 0.2 }
    public var tolerance: TimeInterval { interval / 5 }

    public static func resolve(pointer: CGPoint, island: CGRect, previous: Self?) -> Self {
        // Hysteresis keeps the timer from being replaced on every small movement at the boundary.
        let distance: CGFloat = previous == .near ? 120 : 80
        return island.insetBy(dx: -distance, dy: -distance).contains(pointer) ? .near : .far
    }
}
