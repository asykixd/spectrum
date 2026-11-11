import Foundation
import Testing

@testable import SpectrumCore

@Test func browserPlaybackKeepsMetadataAndAValidatedTarget() throws {
    let output =
        #"+{"token":"0123456789abcdef0123456789abcdef","title":"A song\twith a tab","artist":"Artist","album":"","elapsed":27,"duration":210,"isPlaying":true}"#
    let track = try #require(BrowserMedia.chrome.parse(output, sampledAt: .distantPast))

    #expect(track.title == "A song\twith a tab")
    #expect(track.bundleID == "com.google.Chrome")
    #expect(track.isPlaying)
    #expect(track.elapsed == 27)
    #expect(!track.canSkipTracks)
    let token = try #require(track.browserToken)
    let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app")
    #expect(
        BrowserMedia.chrome.toggleScript(token: token, applicationURL: chrome)?.contains(token)
            == true)
    #expect(BrowserMedia.chrome.toggleScript(token: "\"\"", applicationURL: chrome) == nil)
    #expect(
        BrowserMedia.chrome.parse(
            output.replacingOccurrences(of: "210", with: "1e200"), sampledAt: .now) == nil)

    var otherTab = track
    otherTab.browserToken = "1123456789abcdef0123456789abcdef"
    #expect(!otherTab.isSameTrack(as: track))
}

@Test func extraPlaybackSourcesHaveNoNextTrackCommand() throws {
    let track = try #require(
        NowPlaying.parse(
            scriptOutput: "playing\tClip.mov\t\t\t80\t12\t\t42",
            bundleID: "com.apple.QuickTimePlayerX", sampledAt: .distantPast))
    #expect(track.trackURI == "42")
    #expect(!track.canSkipTracks)
    #expect(!SpectrumSettings().showExtraPlayers)
}
