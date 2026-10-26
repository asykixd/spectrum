import Foundation

/// The track reported by the system now-playing service.
///
/// Decoded from one JSON line printed by the `SpectrumMediaHelper` library.
public struct NowPlaying: Decodable, Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval
    public var elapsed: TimeInterval
    /// When `elapsed` was sampled, in seconds since 1970.
    public var timestamp: TimeInterval
    public var rate: Double
    public var isPlaying: Bool
    public var bundleID: String?
    public var artwork: Data?

    enum CodingKeys: String, CodingKey {
        case title, artist, album, duration, elapsed, timestamp, rate, bundleID, artwork
        case isPlaying = "playing"
    }

    public init(
        title: String, artist: String, album: String = "", duration: TimeInterval = 0,
        elapsed: TimeInterval = 0, timestamp: TimeInterval = 0, rate: Double = 1,
        isPlaying: Bool, bundleID: String? = nil, artwork: Data? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.timestamp = timestamp
        self.rate = rate
        self.isPlaying = isPlaying
        self.bundleID = bundleID
        self.artwork = artwork
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        artist = try container.decodeIfPresent(String.self, forKey: .artist) ?? ""
        album = try container.decodeIfPresent(String.self, forKey: .album) ?? ""
        duration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        elapsed = try container.decodeIfPresent(Double.self, forKey: .elapsed) ?? 0
        timestamp = try container.decodeIfPresent(Double.self, forKey: .timestamp) ?? 0
        rate = try container.decodeIfPresent(Double.self, forKey: .rate) ?? 1
        isPlaying = try container.decode(Bool.self, forKey: .isPlaying)
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
        artwork = try container.decodeIfPresent(String.self, forKey: .artwork)
            .flatMap { Data(base64Encoded: $0) }
    }

    public static func decodeLine(_ line: Data) throws -> NowPlaying {
        try JSONDecoder().decode(NowPlaying.self, from: line)
    }

    public var hasTrack: Bool { !title.isEmpty }

    /// Playback position extrapolated from the last sample.
    public func position(at date: Date) -> TimeInterval {
        guard isPlaying, timestamp > 0 else { return clamped(elapsed) }
        return clamped(elapsed + (date.timeIntervalSince1970 - timestamp) * rate)
    }

    private func clamped(_ value: TimeInterval) -> TimeInterval {
        duration > 0 ? min(max(value, 0), duration) : max(value, 0)
    }
}

/// Commands understood by `MRMediaRemoteSendCommand`.
public enum MediaCommand: Int, Sendable {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5
}
