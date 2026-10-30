import Foundation

/// How often to read the Claude app's accessibility tree.
///
/// Each read costs CPU in Spectrum and keeps Electron maintaining its accessibility tree in the
/// Claude app, so reads slow down when nobody is looking and pause on battery.
public enum ChatPollPolicy {
    /// Seconds between reads, or nil to skip reading for now.
    public static func interval(
        panelOpen: Bool, claudeFrontmost: Bool, onBattery: Bool, pauseOnBattery: Bool
    ) -> TimeInterval? {
        if panelOpen { return 2 }
        if onBattery && pauseOnBattery { return nil }
        return claudeFrontmost ? 2 : 10
    }

    /// Seconds between timer ticks. While reads are paused the timer still ticks now and then,
    /// so plugging in the charger resumes reading.
    public static func period(reading interval: TimeInterval?) -> TimeInterval {
        interval ?? 30
    }
}
