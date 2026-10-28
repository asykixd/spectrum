/// What the notch shows, mirroring Dynamic Island states.
public enum NotchMode: Hashable, Sendable {
    /// Nothing outside the hardware notch: Spectrum looks like it isn't running.
    case hidden
    /// Music is playing: artwork and waveform on the notch ears.
    case compact
    /// Pointer over the live activity: full player controls.
    case expanded
    /// Agents panel opened with a double tap of ⌘.
    case agents
    /// An agent needs permission or an answer: the island blinks until the user looks.
    case attention
    /// A task just finished: a checkmark for a moment.
    case done

    public static func resolve(
        current: NotchMode, isPlaying: Bool, hasTrack: Bool, isHovering: Bool,
        agentsOpen: Bool, signal: AttentionTracker.Signal? = nil
    ) -> NotchMode {
        if agentsOpen { return .agents }
        // Hover only grows an activity that is already visible, and keeps it open after a pause
        // so the user can press play again.
        if isHovering, hasTrack, current == .compact || current == .expanded {
            return .expanded
        }
        switch signal {
        case .needsYou: return .attention
        case .done: return .done
        case nil: return isPlaying ? .compact : .hidden
        }
    }
}
