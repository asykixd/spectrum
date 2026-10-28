import SpectrumCore
import SwiftUI

/// The island calling for the user, kept deliberately quiet: small icons on the notch ears,
/// plus a blinking outline while an agent waits.
struct SignalView: View {
    let model: NotchModel

    var body: some View {
        switch model.signal {
        case .needsYou(let session):
            NeedsYouView(notch: model.geometry.notch.size, sessionID: session.id)
                .contentShape(Rectangle())
                .onTapGesture(perform: model.answerAttention)
        case .done(let session):
            Self.ears(notch: model.geometry.notch.size) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Self.green.opacity(0.85))
                    .symbolEffect(.bounce, value: session.id)
            }
        case nil:
            Color.clear
        }
    }

    static let green = Color(hex: 0x4ADE80)
    static let amber = Color(hex: 0xF59E0B)

    /// A small icon in the left ear; the right ear stays empty so the hardware notch reads as one
    /// quiet pill.
    fileprivate static func ears<Icon: View>(
        notch: CGSize, @ViewBuilder icon: () -> Icon
    ) -> some View {
        HStack(spacing: 0) {
            icon().frame(width: NotchLayout.signalEarWidth)
            Spacer().frame(width: notch.width)
            Spacer().frame(width: NotchLayout.signalEarWidth)
        }
        .frame(height: notch.height)
    }

    /// Persistent until answered: a warning icon and a thin outline that blink.
    private struct NeedsYouView: View {
        let notch: CGSize
        let sessionID: String

        var body: some View {
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate
                let blink = 0.5 + 0.5 * sin(phase * 4)
                SignalView.ears(notch: notch) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SignalView.amber.opacity(0.5 + 0.4 * blink))
                }
                .overlay(
                    UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                        .strokeBorder(
                            SignalView.amber.opacity(0.15 + 0.45 * blink), lineWidth: 1)
                )
            }
        }
    }
}
