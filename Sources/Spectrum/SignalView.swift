import SpectrumCore
import SwiftUI

/// The island calling for the user: a pulsing request, or a brief checkmark.
struct SignalView: View {
    let model: NotchModel

    var body: some View {
        switch model.signal {
        case .needsYou(let session):
            NeedsYouView(session: session, style: model.settings.characters)
                .contentShape(Rectangle())
                .onTapGesture(perform: model.answerAttention)
        case .done(let session):
            ears(notch: model.geometry.notch.width) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x4ADE80))
                    .symbolEffect(.bounce, value: session.id)
            } right: {
                name(session.projectName, detail: "done")
            }
        case nil:
            Color.clear
        }
    }

    private func ears<Left: View, Right: View>(
        notch: CGFloat, @ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right
    ) -> some View {
        HStack(spacing: 0) {
            left().frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(width: notch)
            right().frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: model.geometry.notch.height)
    }

    private func name(_ text: String, detail: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
            Text(detail)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .lineLimit(1)
    }

    /// Persistent until answered: the island breathes an orange glow and the agent waves.
    private struct NeedsYouView: View {
        let session: AgentSession
        let style: SpectrumSettings.CharacterStyle

        var body: some View {
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate
                let pulse = 0.5 + 0.5 * sin(phase * 4)
                HStack(spacing: 8) {
                    AgentAvatar(session: session, style: style)
                        .scaleEffect(0.75 + 0.06 * pulse)
                        .frame(width: 24, height: 24)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(session.projectName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("needs you")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(hex: 0xF59E0B))
                    }
                    .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .frame(maxHeight: .infinity)
                .overlay(
                    UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                        .strokeBorder(
                            Color(hex: 0xF59E0B).opacity(0.35 + 0.6 * pulse), lineWidth: 2)
                )
                .background(
                    UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                        .fill(Color(hex: 0xF59E0B).opacity(0.12 * pulse))
                )
            }
        }
    }
}
