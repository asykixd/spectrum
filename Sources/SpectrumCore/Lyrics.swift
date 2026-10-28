import Foundation

/// Time-synced lyrics in the LRC format: `[mm:ss.xx] text`.
public struct Lyrics: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public let time: TimeInterval
        public let text: String
    }

    public let lines: [Line]

    /// Nil when the text has no timed lines, e.g. plain lyrics.
    public init?(lrc: String) {
        var lines: [Line] = []
        for raw in lrc.split(separator: "\n") {
            var rest = Substring(raw)
            var times: [TimeInterval] = []
            // A line can carry several timestamps when it repeats, like a chorus.
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                guard let time = Self.seconds(tag) else { break }
                times.append(time)
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            lines += times.map { Line(time: $0, text: text) }
        }
        guard !lines.isEmpty else { return nil }
        self.lines = lines.sorted { $0.time < $1.time }
    }

    /// The line being sung at `position`, or nil before the first one and during breaks.
    public func line(at position: TimeInterval) -> String? {
        guard let current = lines.last(where: { $0.time <= position }), !current.text.isEmpty
        else { return nil }
        return current.text
    }

    /// `mm:ss.xx`; metadata tags like `ar: Artist` don't parse.
    private static func seconds(_ tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1])
        else { return nil }
        return minutes * 60 + seconds
    }
}

/// lrclib.net: a free, open lyrics database with synced lyrics and no API key.
public enum LRCLib {
    public static func url(for track: NowPlaying) -> URL? {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        var items = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
        ]
        if !track.album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: track.album))
        }
        // The duration narrows the match to the right recording.
        if track.duration > 0 {
            items.append(
                URLQueryItem(name: "duration", value: String(Int(track.duration.rounded()))))
        }
        components?.queryItems = items
        return components?.url
    }

    private struct Response: Decodable {
        let syncedLyrics: String?
    }

    public static func lyrics(from data: Data) -> Lyrics? {
        guard let synced = (try? JSONDecoder().decode(Response.self, from: data))?.syncedLyrics
        else { return nil }
        return Lyrics(lrc: synced)
    }
}
