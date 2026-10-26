/// Closes a panel once the pointer has been inside it and then leaves.
///
/// A panel opened from the keyboard may appear far from the pointer; it stays open until the
/// user has visited it, so it doesn't vanish before they reach it.
public struct HoverDismissal: Sendable {
    private var visited = false

    public init() {}

    /// Returns true when the panel should close now.
    public mutating func update(isOpen: Bool, isInside: Bool) -> Bool {
        guard isOpen else {
            visited = false
            return false
        }
        if isInside {
            visited = true
            return false
        }
        if visited {
            visited = false
            return true
        }
        return false
    }
}
