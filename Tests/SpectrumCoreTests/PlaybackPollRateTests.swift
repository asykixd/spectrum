import Testing

@testable import SpectrumCore

@Test func playbackPollsForPausedNativePlayersAndSourcesWithoutNotifications() {
    #expect(
        PlaybackPollRate.resolve(
            nativePlaying: false, nativePaused: false, extraSourcesRunning: false) == nil)
    #expect(
        PlaybackPollRate.resolve(
            nativePlaying: true, nativePaused: true, extraSourcesRunning: true) == nil)
    #expect(
        PlaybackPollRate.resolve(
            nativePlaying: false, nativePaused: true, extraSourcesRunning: true)
            == .pausedNativePlayer)
    #expect(
        PlaybackPollRate.resolve(
            nativePlaying: false, nativePaused: false, extraSourcesRunning: true) == .extraSources)
}
