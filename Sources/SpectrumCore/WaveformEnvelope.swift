import Foundation

/// The waveform shows four successive measurements of the audio level.
public struct WaveformEnvelope: Sendable {
    public private(set) var levels = [Double](repeating: 0.12, count: 4)

    public init() {}

    public mutating func append(rms: Float) {
        let amplitude = rms.isFinite ? max(Double(rms), 0.001) : 0.001
        let decibels = 20 * log10(amplitude)
        let level = 0.12 + 0.88 * min(max((decibels + 48) / 48, 0), 1)
        levels.removeFirst()
        levels.append(level)
    }
}
