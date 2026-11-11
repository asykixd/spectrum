import Foundation

public enum PlaybackPollRate: Equatable, Sendable {
    case pausedNativePlayer
    case extraSources

    public var interval: TimeInterval { self == .pausedNativePlayer ? 3 : 6 }

    public static func resolve(
        nativePlaying: Bool, nativePaused: Bool, extraSourcesRunning: Bool
    ) -> Self? {
        if nativePlaying { return nil }
        if nativePaused { return .pausedNativePlayer }
        return extraSourcesRunning ? .extraSources : nil
    }
}
