import Foundation

/// The track a music player reports through its AppleScript dictionary.
public struct NowPlaying: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval
    public var elapsed: TimeInterval
    /// When `elapsed` was sampled.
    public var sampledAt: Date
    public var isPlaying: Bool
    public var bundleID: String
    public var artworkURL: URL?
    /// Player-specific track id, e.g. `spotify:track:6sdT…`.
    public var trackURI: String?

    public init(
        title: String, artist: String, album: String = "", duration: TimeInterval = 0,
        elapsed: TimeInterval = 0, sampledAt: Date = .distantPast, isPlaying: Bool,
        bundleID: String, artworkURL: URL? = nil, trackURI: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.sampledAt = sampledAt
        self.isPlaying = isPlaying
        self.bundleID = bundleID
        self.artworkURL = artworkURL
        self.trackURI = trackURI
    }

    /// Parses the tab-separated line produced by Spectrum's player scripts:
    /// `state, title, artist, album, duration (s), position (s), artwork URL, track URI`.
    ///
    /// Returns nil when the player has no current track.
    public static func parse(scriptOutput: String, bundleID: String, sampledAt: Date) -> NowPlaying?
    {
        let fields = scriptOutput.components(separatedBy: "\t")
        guard fields.count >= 6, !fields[1].isEmpty else { return nil }
        return NowPlaying(
            title: fields[1],
            artist: fields[2],
            album: fields[3],
            duration: number(fields[4]),
            elapsed: number(fields[5]),
            sampledAt: sampledAt,
            isPlaying: fields[0] == "playing",
            bundleID: bundleID,
            artworkURL: fields.count > 6 ? URL(string: fields[6]).flatMap(validURL) : nil,
            trackURI: fields.count > 7 && !fields[7].isEmpty ? fields[7] : nil
        )
    }

    /// Same track, ignoring playback position: used to avoid refetching artwork.
    public func isSameTrack(as other: NowPlaying?) -> Bool {
        guard let other else { return false }
        if let trackURI, let otherURI = other.trackURI { return trackURI == otherURI }
        return title == other.title && artist == other.artist && album == other.album
            && bundleID == other.bundleID
    }

    /// Playback position extrapolated from the last sample.
    public func position(at date: Date) -> TimeInterval {
        let value = isPlaying ? elapsed + date.timeIntervalSince(sampledAt) : elapsed
        return duration > 0 ? min(max(value, 0), duration) : max(value, 0)
    }

    /// AppleScript formats numbers with the user's locale, e.g. "212,5" in Russian.
    private static func number(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private static func validURL(_ url: URL) -> URL? {
        url.scheme == "https" || url.scheme == "http" ? url : nil
    }
}

/// Spotify's AppleScript reports only the first artist; the public embed page lists them all.
public enum SpotifyEmbed {
    private struct Artist: Decodable {
        let name: String
    }

    /// Embed page for a `spotify:track:<id>` URI.
    public static func url(forTrackURI uri: String) -> URL? {
        let prefix = "spotify:track:"
        guard uri.hasPrefix(prefix) else { return nil }
        return URL(string: "https://open.spotify.com/embed/track/\(uri.dropFirst(prefix.count))")
    }

    /// Artist names from the first `"artists":[…]` array in the page's embedded JSON.
    public static func artists(fromHTML html: String) -> [String] {
        guard let start = html.range(of: #""artists":["#) else { return [] }
        let arrayStart = html.index(before: start.upperBound)
        var depth = 0
        var end: String.Index?
        for index in html[arrayStart...].indices {
            switch html[index] {
            case "[": depth += 1
            case "]":
                depth -= 1
                if depth == 0 { end = index }
            default: break
            }
            if end != nil { break }
        }
        guard let end,
            let artists = try? JSONDecoder().decode(
                [Artist].self, from: Data(html[arrayStart...end].utf8))
        else { return [] }
        return artists.map(\.name)
    }
}

public enum MediaCommand: Sendable {
    case togglePlayPause
    case nextTrack
    case previousTrack
}
