import Foundation
import Testing

@testable import SpectrumCore

@Test func decodesHelperLine() throws {
    let line = Data(
        #"{"title":"Song","artist":"Band","duration":200,"elapsed":10,"timestamp":1000,"rate":1,"playing":true,"bundleID":"com.spotify.client","artwork":"AQI="}"#
            .utf8)

    let track = try NowPlaying.decodeLine(line)

    #expect(track.title == "Song")
    #expect(track.artist == "Band")
    #expect(track.album.isEmpty)
    #expect(track.isPlaying)
    #expect(track.bundleID == "com.spotify.client")
    #expect(track.artwork == Data([1, 2]))
}

@Test func emptyHelperLineMeansNoTrack() throws {
    let track = try NowPlaying.decodeLine(Data(#"{"playing":false}"#.utf8))

    #expect(!track.hasTrack)
}

@Test func positionAdvancesOnlyWhilePlaying() {
    var track = NowPlaying(
        title: "Song", artist: "Band", duration: 100, elapsed: 10, timestamp: 1000, isPlaying: true)

    #expect(track.position(at: Date(timeIntervalSince1970: 1005)) == 15)
    #expect(track.position(at: Date(timeIntervalSince1970: 2000)) == 100)

    track.isPlaying = false
    #expect(track.position(at: Date(timeIntervalSince1970: 1005)) == 10)
}
