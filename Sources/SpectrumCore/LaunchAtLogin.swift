import ServiceManagement

/// The system owns login-item state, including changes made outside Spectrum.
public enum LaunchAtLogin: Equatable, Sendable {
    case off
    case on
    case needsApproval
    case unavailable

    public enum Change: Equatable, Sendable {
        case register
        case unregister
    }

    public init(_ status: SMAppService.Status) {
        switch status {
        case .notRegistered: self = .off
        case .enabled: self = .on
        case .requiresApproval: self = .needsApproval
        case .notFound: self = .unavailable
        @unknown default: self = .unavailable
        }
    }

    /// A registration awaiting approval can still be turned off in Spectrum.
    public var isRequested: Bool { self == .on || self == .needsApproval }

    public func change(to enabled: Bool) -> Change? {
        guard self != .unavailable, enabled != isRequested else { return nil }
        return enabled ? .register : .unregister
    }
}
