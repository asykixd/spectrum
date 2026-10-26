/// Trackpad feedback Spectrum plays; mapped to `NSHapticFeedbackManager` patterns by the app.
public enum HapticCue: Equatable, Sendable {
    /// The island grows into an interactive state.
    case expand
    /// The island shrinks back.
    case collapse
    /// A control was pressed or a gesture recognised.
    case tap

    /// Feedback for a mode change, or nil when the user likely isn't touching the trackpad
    /// (music starting or stopping on its own).
    public static func forTransition(from old: NotchMode, to new: NotchMode) -> HapticCue? {
        let interactive: Set<NotchMode> = [.expanded, .agents]
        switch (interactive.contains(old), interactive.contains(new)) {
        case (false, true): return .expand
        case (true, false): return .collapse
        case (true, true): return old == new ? nil : .expand
        case (false, false): return nil
        }
    }
}
