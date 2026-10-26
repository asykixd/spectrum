import AppKit
import CoreImage
import SpectrumCore
import SwiftUI

/// Runs NSAppleScript on one serial queue: it is not thread-safe, and player round trips can
/// take tens of milliseconds, which would stutter animations on the main thread.
private final class ScriptRunner: @unchecked Sendable {
    /// What callers need from a script's result. The descriptor itself isn't Sendable, so it
    /// never leaves the script queue.
    struct Output: Sendable {
        var string: String?
        var data: Data?
    }

    private let queue = DispatchQueue(label: "spectrum.applescript")
    private var cache: [String: NSAppleScript] = [:]

    @discardableResult
    func run(_ source: String) async -> Output {
        await withCheckedContinuation { continuation in
            queue.async {
                let result = self.execute(source)
                continuation.resume(
                    returning: Output(string: result?.stringValue, data: result?.data))
            }
        }
    }

    private func execute(_ source: String) -> NSAppleEventDescriptor? {
        let script = cache[source] ?? NSAppleScript(source: source)
        cache[source] = script
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        if let error {
            log.debug("applescript failed: \(error, privacy: .public)")
        }
        return result
    }
}

private struct Player {
    let bundleID: String
    let stateScript: String
    let commands: [MediaCommand: String]

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}

private let players = [
    Player(
        bundleID: "com.spotify.client",
        stateScript: """
            tell application id "com.spotify.client"
                try
                    set t to current track
                    return (player state as string) & tab & (name of t) & tab & (artist of t) & tab & (album of t) & tab & ((duration of t) / 1000 as string) & tab & (player position as string) & tab & (artwork url of t) & tab & (id of t)
                on error
                    return "stopped"
                end try
            end tell
            """,
        commands: [
            .togglePlayPause: "playpause", .nextTrack: "next track",
            .previousTrack: "previous track",
        ]
    ),
    Player(
        bundleID: "com.apple.Music",
        stateScript: """
            tell application id "com.apple.Music"
                try
                    if player state is stopped then return "stopped"
                    set t to current track
                    return (player state as string) & tab & (name of t) & tab & (artist of t) & tab & (album of t) & tab & ((duration of t) as string) & tab & (player position as string) & tab & ""
                on error
                    return "stopped"
                end try
            end tell
            """,
        commands: [
            .togglePlayPause: "playpause", .nextTrack: "next track",
            .previousTrack: "previous track",
        ]
    ),
]

/// Feeds the model with the current track from Spotify and Apple Music.
///
/// MediaRemote would cover every player, but since macOS 15.4 it ignores third-party apps, so
/// Spectrum asks the players directly. That needs Automation permission per player.
@MainActor
final class NowPlayingMonitor {
    private let model: NotchModel
    private let runner = ScriptRunner()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var refreshing = false
    /// Full artist lists by Spotify track URI; AppleScript only knows the first artist.
    private var spotifyArtists: [String: String] = [:]

    init(model: NotchModel) {
        self.model = model
    }

    func start() {
        // A slow safety-net poll: the players' own notifications deliver changes instantly,
        // and the position between samples is extrapolated.
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 1
        // Both players broadcast state changes, which makes play/pause feel instant.
        let center = DistributedNotificationCenter.default()
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            observers.append(
                center.addObserver(forName: .init(name), object: nil, queue: .main) {
                    [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                })
        }
        refresh()
    }

    func send(_ command: MediaCommand) {
        guard let bundleID = model.nowPlaying?.bundleID,
            let player = players.first(where: { $0.bundleID == bundleID }),
            let verb = player.commands[command]
        else { return }
        Task {
            await runner.run("tell application id \"\(bundleID)\" to \(verb)")
            refresh()
        }
    }

    private func refresh() {
        guard !refreshing else { return }
        refreshing = true
        Task {
            defer { refreshing = false }
            var tracks: [NowPlaying] = []
            for player in players where player.isRunning {
                let output = await runner.run(player.stateScript).string ?? ""
                if let track = NowPlaying.parse(
                    scriptOutput: output, bundleID: player.bundleID, sampledAt: Date())
                {
                    tracks.append(track)
                }
            }
            apply(tracks.first(where: \.isPlaying) ?? tracks.first)
        }
    }

    private func apply(_ reported: NowPlaying?) {
        var track = reported
        if let uri = track?.trackURI, let artists = spotifyArtists[uri] {
            track?.artist = artists
        }
        let previous = model.nowPlaying
        if track != previous { model.nowPlaying = track }
        guard let track, !track.isSameTrack(as: previous) else { return }
        model.artwork = nil
        model.accent = .white
        Task { await loadArtwork(for: track) }
        if let uri = track.trackURI, spotifyArtists[uri] == nil {
            Task { await loadSpotifyArtists(uri: uri) }
        }
    }

    private func loadSpotifyArtists(uri: String) async {
        guard let url = SpotifyEmbed.url(forTrackURI: uri),
            let (data, _) = try? await URLSession.shared.data(from: url)
        else { return }
        let artists = SpotifyEmbed.artists(fromHTML: String(decoding: data, as: UTF8.self))
        guard !artists.isEmpty else { return }
        spotifyArtists[uri] = artists.joined(separator: ", ")
        if model.nowPlaying?.trackURI == uri {
            model.nowPlaying?.artist = artists.joined(separator: ", ")
        }
    }

    private func loadArtwork(for track: NowPlaying) async {
        var data: Data?
        if let url = track.artworkURL {
            data = try? await URLSession.shared.data(from: url).0
        } else if track.bundleID == "com.apple.Music" {
            data =
                await runner.run(
                    "tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track"
                ).data
        }
        // The track may have changed while the artwork was loading.
        guard let data, let image = NSImage(data: data),
            model.nowPlaying?.isSameTrack(as: track) == true
        else { return }
        model.artwork = image
        model.accent = image.accentColor ?? .white
    }
}

extension NSImage {
    /// Average color, brightened so the waveform stays visible on black.
    fileprivate var accentColor: Color? {
        guard let tiff = tiffRepresentation, let input = CIImage(data: tiff),
            let filter = CIFilter(
                name: "CIAreaAverage",
                parameters: [
                    kCIInputImageKey: input,
                    kCIInputExtentKey: CIVector(cgRect: input.extent),
                ]),
            let output = filter.outputImage
        else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(
            output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let color = NSColor(
            red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        return Color(
            hue: hue, saturation: min(saturation * 1.2, 0.85), brightness: max(brightness, 0.8))
    }
}
