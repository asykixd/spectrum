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
    func run(_ source: String, cacheScript: Bool = true) async -> Output {
        await withCheckedContinuation { continuation in
            queue.async {
                let result = self.execute(source, cacheScript: cacheScript)
                continuation.resume(
                    returning: Output(string: result?.stringValue, data: result?.data))
            }
        }
    }

    private func execute(_ source: String, cacheScript: Bool) -> NSAppleEventDescriptor? {
        let script = cache[source] ?? NSAppleScript(source: source)
        if cacheScript { cache[source] = script }
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        if let error {
            log.debug("applescript failed: \(error)")
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

private enum QuickTimeMedia {
    static let bundleID = "com.apple.QuickTimePlayerX"
    static let sample = """
        tell application "/System/Applications/QuickTime Player.app"
            if not (exists front window) then return ""
            set movieWindow to front window
            set movieDocument to document of movieWindow
            if duration of movieDocument is not greater than 0 then return ""
            set stateName to "paused"
            if playing of movieDocument then set stateName to "playing"
            return stateName & tab & (name of movieDocument) & tab & tab & tab & (duration of movieDocument as text) & tab & (current time of movieDocument as text) & tab & tab & (id of movieWindow as text)
        end tell
        """

    static func toggle(window: String?) -> String? {
        guard let window, let id = Int(window), id > 0 else { return nil }
        return """
            tell application "/System/Applications/QuickTime Player.app"
                if not (exists window id \(id)) then return
                set movieDocument to document of window id \(id)
                if playing of movieDocument then
                    pause movieDocument
                else
                    play movieDocument
                end if
            end tell
            """
    }
}

/// Feeds the model with the current track from the configured playback sources.
///
/// MediaRemote would cover every player, but since macOS 15.4 it ignores third-party apps, so
/// Spectrum asks the players directly. That needs Automation permission per player.
@MainActor
final class NowPlayingMonitor {
    private let model: NotchModel
    private let runner = ScriptRunner()
    private var timer: Timer?
    private var pollRate: PlaybackPollRate?
    private var observers: [NSObjectProtocol] = []
    private var refreshing = false
    private var refreshPending = false
    private var extraTracks: [NowPlaying] = []
    private var nextExtraSample = Date.distantPast
    /// Full artist lists by Spotify track URI; AppleScript only knows the first artist.
    private var spotifyArtists: [String: String] = [:]

    init(model: NotchModel) {
        self.model = model
    }

    func start() {
        // Both players broadcast state changes, which makes play/pause feel instant.
        let center = DistributedNotificationCenter.default()
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            observers.append(
                center.addObserver(forName: .init(name), object: nil, queue: .main) {
                    [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                })
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let bundleIDs = Set(players.map(\.bundleID) + Self.extraSourceIDs)
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ] {
            observers.append(
                workspace.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] notification in
                    guard
                        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                            as? NSRunningApplication,
                        let bundleID = app.bundleIdentifier, bundleIDs.contains(bundleID)
                    else { return }
                    MainActor.assumeIsolated {
                        self?.nextExtraSample = .distantPast
                        self?.refresh()
                    }
                })
        }
        refresh()
    }

    func settingsChanged() {
        nextExtraSample = .distantPast
        if model.settings.showMusic {
            refresh()
        } else {
            extraTracks = []
            schedulePoll(nil)
            apply(nil)
        }
    }

    func send(_ command: MediaCommand) {
        guard let track = model.nowPlaying, Self.isRunning(track.bundleID) else { return }
        let script: String
        if let player = players.first(where: { $0.bundleID == track.bundleID }),
            let verb = player.commands[command]
        {
            script = "tell application id \"\(track.bundleID)\" to \(verb)"
        } else {
            guard command == .togglePlayPause, model.settings.showExtraPlayers else { return }
            let source = BrowserMedia.allCases.first { $0.bundleID == track.bundleID }
            if let source, let token = track.browserToken,
                let url = Self.runningApplication(track.bundleID)?.bundleURL,
                let toggle = source.toggleScript(token: token, applicationURL: url)
            {
                script = toggle
            } else if track.bundleID == QuickTimeMedia.bundleID,
                let toggle = QuickTimeMedia.toggle(window: track.trackURI)
            {
                script = toggle
            } else {
                return
            }
        }
        Task {
            await runner.run(script, cacheScript: track.canSkipTracks)
            nextExtraSample = .distantPast
            refresh()
        }
    }

    private func refresh() {
        guard model.settings.showMusic else { return }
        guard !refreshing else {
            refreshPending = true
            return
        }
        refreshing = true
        Task {
            defer {
                refreshing = false
                if refreshPending {
                    refreshPending = false
                    refresh()
                }
            }
            var tracks: [NowPlaying] = []
            for player in players where player.isRunning {
                let output = await runner.run(player.stateScript).string ?? ""
                if let track = NowPlaying.parse(
                    scriptOutput: output, bundleID: player.bundleID, sampledAt: Date())
                {
                    tracks.append(track)
                }
            }
            guard model.settings.showMusic else { return }
            let nativePlaying = tracks.contains(where: \.isPlaying)
            let nativePaused = !tracks.isEmpty && !nativePlaying
            let extraRunning =
                model.settings.showExtraPlayers
                && Self.extraSourceIDs.contains(where: Self.isRunning)
            if extraRunning {
                if !nativePlaying, Date() >= nextExtraSample {
                    extraTracks = await sampleExtraPlayers()
                    nextExtraSample = Date().addingTimeInterval(6)
                }
                if model.settings.showMusic && model.settings.showExtraPlayers {
                    tracks += extraTracks.filter { Self.isRunning($0.bundleID) }
                }
            } else {
                extraTracks = []
                nextExtraSample = .distantPast
            }
            guard model.settings.showMusic else { return }
            schedulePoll(
                PlaybackPollRate.resolve(
                    nativePlaying: nativePlaying, nativePaused: nativePaused,
                    extraSourcesRunning: model.settings.showExtraPlayers && extraRunning))
            let previous = model.nowPlaying
            apply(
                tracks.first(where: \.isPlaying)
                    ?? tracks.first { $0.isSameTrack(as: previous) } ?? tracks.first)
        }
    }

    private func schedulePoll(_ rate: PlaybackPollRate?) {
        guard pollRate != rate else { return }
        timer?.invalidate()
        timer = nil
        pollRate = rate
        guard let rate else { return }
        timer = Timer.scheduledTimer(withTimeInterval: rate.interval, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = rate.interval / 3
    }

    private func sampleExtraPlayers() async -> [NowPlaying] {
        var tracks: [NowPlaying] = []
        if Self.isRunning(QuickTimeMedia.bundleID),
            let output = await runner.run(QuickTimeMedia.sample).string,
            let track = NowPlaying.parse(
                scriptOutput: output, bundleID: QuickTimeMedia.bundleID, sampledAt: Date())
        {
            tracks.append(track)
        }
        for browser in BrowserMedia.allCases {
            if let url = Self.runningApplication(browser.bundleID)?.bundleURL,
                let output = await runner.run(browser.sampleScript(applicationURL: url)).string,
                let track = browser.parse(output, sampledAt: Date())
            {
                tracks.append(track)
            }
        }
        return tracks
    }

    private static func isRunning(_ bundleID: String) -> Bool {
        runningApplication(bundleID) != nil
    }

    private static let extraSourceIDs =
        [QuickTimeMedia.bundleID] + BrowserMedia.allCases.map(\.bundleID)

    private static func runningApplication(_ bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
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
        model.lyrics = nil
        Task { await loadArtwork(for: track) }
        if track.canSkipTracks && model.settings.showLyrics {
            // The player's own artist field: featured artists added later would miss the match.
            Task { await loadLyrics(for: track) }
        }
        if track.bundleID == "com.spotify.client", let uri = track.trackURI,
            spotifyArtists[uri] == nil
        {
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

    private func loadLyrics(for track: NowPlaying) async {
        guard let url = LRCLib.url(for: track) else { return }
        var request = URLRequest(url: url)
        // lrclib asks clients to identify themselves.
        request.setValue(
            "Spectrum (https://github.com/asykixd/spectrum)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let lyrics = LRCLib.lyrics(from: data),
            model.nowPlaying?.isSameTrack(as: track) == true
        else { return }
        model.lyrics = lyrics
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
