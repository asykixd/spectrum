import Foundation
import Testing

@testable import SpectrumCore

private let sampledAt = Date(timeIntervalSince1970: 1000)

@Test func parsesSpotifyLineWithLocalizedNumbers() throws {
    let line = "playing\tSong\tBand\tAlbum\t212,5\t10,25\thttps://i.scdn.co/image/abc"

    let track = try #require(
        NowPlaying.parse(scriptOutput: line, bundleID: "com.spotify.client", sampledAt: sampledAt))

    #expect(track.title == "Song")
    #expect(track.artist == "Band")
    #expect(track.duration == 212.5)
    #expect(track.elapsed == 10.25)
    #expect(track.isPlaying)
    #expect(track.artworkURL == URL(string: "https://i.scdn.co/image/abc"))
}

@Test func pausedTrackWithoutArtwork() throws {
    let line = "paused\tSong\tBand\t\t200\t5\t"

    let track = try #require(
        NowPlaying.parse(scriptOutput: line, bundleID: "com.apple.Music", sampledAt: sampledAt))

    #expect(!track.isPlaying)
    #expect(track.artworkURL == nil)
}

@Test func noTrackMeansNil() {
    #expect(NowPlaying.parse(scriptOutput: "stopped", bundleID: "x", sampledAt: sampledAt) == nil)
    #expect(
        NowPlaying.parse(scriptOutput: "stopped\t\t\t\t0\t0", bundleID: "x", sampledAt: sampledAt)
            == nil)
}

@Test func positionAdvancesOnlyWhilePlaying() {
    var track = NowPlaying(
        title: "Song", artist: "Band", duration: 100, elapsed: 10, sampledAt: sampledAt,
        isPlaying: true, bundleID: "x")

    #expect(track.position(at: sampledAt.addingTimeInterval(5)) == 15)
    #expect(track.position(at: sampledAt.addingTimeInterval(500)) == 100)

    track.isPlaying = false
    #expect(track.position(at: sampledAt.addingTimeInterval(5)) == 10)
}

@Test func sameTrackIgnoresPosition() {
    let first = NowPlaying(title: "A", artist: "B", elapsed: 1, isPlaying: true, bundleID: "x")
    var later = first
    later.elapsed = 50

    #expect(later.isSameTrack(as: first))
    #expect(!later.isSameTrack(as: nil))
}

@Test func parsesSpotifyTrackURI() throws {
    let line = "playing\tSong\tA\t\t100\t1\thttps://i.scdn.co/x\tspotify:track:6sdT"

    let track = try #require(
        NowPlaying.parse(scriptOutput: line, bundleID: "com.spotify.client", sampledAt: sampledAt))

    #expect(track.trackURI == "spotify:track:6sdT")
    #expect(
        SpotifyEmbed.url(forTrackURI: "spotify:track:6sdT")
            == URL(string: "https://open.spotify.com/embed/track/6sdT"))
    #expect(SpotifyEmbed.url(forTrackURI: "spotify:episode:1") == nil)
}

@Test func readsAllArtistsFromEmbedPage() {
    let html = #"""
        <script>{"title":"Song","artists":[{"name":"Sqwore","uri":"spotify:artist:1"},{"name":"rizza","uri":"spotify:artist:2"}],"related":{"artists":[{"name":"Other"}]}}</script>
        """#

    #expect(SpotifyEmbed.artists(fromHTML: html) == ["Sqwore", "rizza"])
    #expect(SpotifyEmbed.artists(fromHTML: "<html></html>").isEmpty)
}
