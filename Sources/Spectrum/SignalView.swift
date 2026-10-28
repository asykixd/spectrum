import SpectrumCore
import SwiftUI

/// The island calling for the user, kept deliberately quiet: small icons on the notch ears,
/// plus a blinking outline while an agent waits. With music playing the same icon rides on the
/// artwork instead (see `CompactMusicView`).
struct SignalView: View {
    let model: NotchModel

    var body: some View {
        if let signal = model.signal {
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !signal.isNeedsYou)) {
                timeline in
                let blink = Self.blink(at: timeline.date)
                HStack(spacing: 0) {
                    Icon(signal: signal, blink: blink, size: 11)
                        .frame(width: NotchLayout.signalEarWidth)
                    // The right ear stays empty so the hardware notch reads as one quiet pill.
                    Spacer()
                }
                .frame(height: model.geometry.notch.height)
                .overlay {
                    if signal.isNeedsYou { Self.outline(blink: blink) }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: model.answerAttention)
        } else {
            Color.clear
        }
    }

    static func blink(at date: Date) -> Double {
        0.5 + 0.5 * sin(date.timeIntervalSinceReferenceDate * 4)
    }

    static func outline(blink: Double) -> some View {
        UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
            .strokeBorder(Color(hex: 0xF59E0B).opacity(0.15 + 0.45 * blink), lineWidth: 1)
    }

    /// A blinking warning while an agent waits, a checkmark when it finishes.
    struct Icon: View {
        let signal: AttentionTracker.Signal
        let blink: Double
        let size: CGFloat

        var body: some View {
            switch signal {
            case .needsYou:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xF59E0B).opacity(0.5 + 0.4 * blink))
            case .done(let session):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: size + 1, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x4ADE80).opacity(0.85))
                    .symbolEffect(.bounce, value: session.id)
            }
        }
    }
}

extension AttentionTracker.Signal {
    var isNeedsYou: Bool {
        if case .needsYou = self { return true }
        return false
    }
}
