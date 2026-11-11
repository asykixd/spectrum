/// macOS virtual key codes used only while the notch panel owns keyboard focus.
public enum PanelKey: UInt16, Sendable {
    case enter = 36
    case escape = 53
    case keypadEnter = 76
    case down = 125
    case up = 126

    public var permissionDecision: PermissionDecision? {
        switch self {
        case .enter, .keypadEnter: .allow
        case .escape: .deny
        case .down, .up: nil
        }
    }

    public func move(in orderedIDs: [String], from current: String?) -> String? {
        guard self == .up || self == .down, !orderedIDs.isEmpty else { return nil }
        guard let current, let index = orderedIDs.firstIndex(of: current) else {
            return self == .down ? orderedIDs.first : orderedIDs.last
        }
        let destination = self == .down ? min(index + 1, orderedIDs.count - 1) : max(index - 1, 0)
        return orderedIDs[destination]
    }
}
