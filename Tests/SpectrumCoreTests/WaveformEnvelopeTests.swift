import Testing

@testable import SpectrumCore

@Test func waveformBarsFollowRecentAudioAmplitude() {
    var envelope = WaveformEnvelope()
    envelope.append(rms: 0)
    envelope.append(rms: 0.1)
    envelope.append(rms: 0.5)
    envelope.append(rms: 2)

    let levels = envelope.levels
    #expect(levels.count == 4)
    #expect(levels[0] < levels[1])
    #expect(levels[1] < levels[2])
    #expect(levels[2] < levels[3])
    #expect(levels[3] == 1)

    envelope.append(rms: .nan)
    #expect(envelope.levels == Array(levels.dropFirst()) + [levels[0]])
}
