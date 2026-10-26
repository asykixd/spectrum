import AppKit
import SpectrumCore
import SwiftUI

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color(white: 0.25), Color(white: 0.12)], startPoint: .top,
                        endPoint: .bottom)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Bars that bounce while music plays, tinted with the artwork's color.
struct WaveformView: View {
    let isPlaying: Bool
    let color: Color
    var barCount = 4
    var height: CGFloat = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: height * level(index, time))
                }
            }
            .frame(height: height)
        }
    }

    private func level(_ index: Int, _ time: TimeInterval) -> CGFloat {
        guard isPlaying else { return 0.25 }
        let speeds = [5.3, 7.1, 6.2, 8.4, 5.9]
        let phase = Double(index) * 1.7
        let wave = abs(sin(time * speeds[index % speeds.count] + phase))
        let wobble = abs(sin(time * 2.3 + phase * 0.5))
        return 0.3 + 0.7 * CGFloat(wave * 0.7 + wobble * 0.3)
    }
}

/// Live activity on the notch ears: artwork left, waveform right.
struct CompactMusicView: View {
    let model: NotchModel

    var body: some View {
        HStack(spacing: 0) {
            ArtworkView(image: model.artwork, size: 22, radius: 6)
            Spacer(minLength: 0)
            WaveformView(isPlaying: model.nowPlaying?.isPlaying ?? false, color: model.accent)
        }
        .padding(.horizontal, 10)
        .frame(height: model.geometry.notch.height)
    }
}

struct ExpandedMusicView: View {
    let model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.geometry.notch.height)
            if let track = model.nowPlaying {
                HStack(alignment: .center, spacing: 14) {
                    ArtworkView(image: model.artwork, size: 84, radius: 14)
                        .shadow(color: model.accent.opacity(0.35), radius: 12)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(track.artist)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .lineLimit(1)
                            Spacer(minLength: 8)
                            PlayerIcon(bundleID: track.bundleID)
                        }
                        ProgressRow(track: track, accent: model.accent)
                        Controls(isPlaying: track.isPlaying, send: model.perform)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
    }
}

private struct PlayerIcon: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 18, height: 18)
                .opacity(0.9)
        }
    }
}

private struct ProgressRow: View {
    let track: NowPlaying
    let accent: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let position = track.position(at: timeline.date)
            let fraction = track.duration > 0 ? position / track.duration : 0
            HStack(spacing: 8) {
                Text(format(position))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(accent).frame(width: proxy.size.width * fraction)
                    }
                }
                .frame(height: 4)
                Text("-" + format(max(track.duration - position, 0)))
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct Controls: View {
    let isPlaying: Bool
    let send: (MediaCommand) -> Void

    var body: some View {
        HStack(spacing: 28) {
            button("backward.fill", size: 16) { send(.previousTrack) }
            button(isPlaying ? "pause.fill" : "play.fill", size: 22) { send(.togglePlayPause) }
            button("forward.fill", size: 16) { send(.nextTrack) }
        }
        .frame(maxWidth: .infinity)
    }

    private func button(_ symbol: String, size: CGFloat, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
