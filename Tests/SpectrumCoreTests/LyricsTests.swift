import Foundation
import Testing

@testable import SpectrumCore

@Test func parsesTimedLinesAndSkipsTags() {
    let lyrics = Lyrics(
        lrc: """
            [ar: Neon Coast]
            [00:12.50] Night falls on the highway
            [00:15.00][01:15.00] Midnight drive
            [00:18.20]
            [00:20.00] Into the light
            """)

    #expect(lyrics?.lines.map(\.time) == [12.5, 15, 18.2, 20, 75])
    #expect(lyrics?.line(at: 5) == nil)
    #expect(lyrics?.line(at: 14) == "Night falls on the highway")
    #expect(lyrics?.line(at: 16) == "Midnight drive")
    // An empty timed line is an instrumental break.
    #expect(lyrics?.line(at: 19) == nil)
    #expect(lyrics?.line(at: 80) == "Midnight drive")
}

@Test func noLyricsWithoutTimedLines() {
    #expect(Lyrics(lrc: "Just plain words\nwithout timing") == nil)
}

@Test func lrclibQueryNamesTheTrack() throws {
    let track = NowPlaying(
        title: "Midnight Drive", artist: "Neon Coast", album: "Lumen", duration: 214.6,
        isPlaying: true, bundleID: "com.spotify.client")
    let url = try #require(LRCLib.url(for: track))
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

    #expect(url.host == "lrclib.net")
    #expect(items.first { $0.name == "track_name" }?.value == "Midnight Drive")
    #expect(items.first { $0.name == "artist_name" }?.value == "Neon Coast")
    #expect(items.first { $0.name == "duration" }?.value == "215")
}

@Test func lrclibResponseGivesSyncedLyrics() {
    let json = #"{"id":1,"instrumental":false,"syncedLyrics":"[00:01.00] Hello"}"#
    #expect(LRCLib.lyrics(from: Data(json.utf8))?.line(at: 2) == "Hello")
    #expect(LRCLib.lyrics(from: Data(#"{"syncedLyrics":null}"#.utf8)) == nil)
}
