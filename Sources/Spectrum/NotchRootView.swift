import SpectrumCore
import SwiftUI

struct NotchRootView: View {
    let model: NotchModel

    private var mode: NotchMode { model.mode }
    private var size: CGSize {
        NotchLayout.size(for: mode, geometry: model.geometry, lyrics: model.lyrics != nil)
    }
    private var shape: UnevenRoundedRectangle {
        let radius = NotchLayout.bottomRadius(for: mode)
        let top = model.geometry.hasHardwareNotch ? 0 : radius
        return UnevenRoundedRectangle(
            topLeadingRadius: top, bottomLeadingRadius: radius, bottomTrailingRadius: radius,
            topTrailingRadius: top)
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape.fill(.black)
            content
                .transition(
                    model.renderingStill
                        ? .identity : .opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .shadow(
            color: .black.opacity(
                [.hidden, .compact, .attention, .done].contains(mode) ? 0 : 0.35),
            radius: 18, y: 8
        )
        // Without a hardware notch the hidden island would be a visible black pill.
        .opacity(mode == .hidden && !model.geometry.hasHardwareNotch ? 0 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Stills must show the settled state, not the first frame of a transition.
        .animation(
            model.renderingStill ? nil : .spring(response: 0.42, dampingFraction: 0.8),
            value: mode)
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .hidden:
            Color.clear
        case .compact:
            CompactMusicView(model: model)
        case .expanded:
            ExpandedMusicView(model: model)
        case .agents:
            if model.settings.privacyMode {
                PrivacyPanel(model: model)
            } else {
                AgentsPanelView(model: model)
            }
        case .attention, .done:
            SignalView(model: model)
        case .permission:
            PermissionView(model: model)
        }
    }
}

private struct PrivacyPanel: View {
    let model: NotchModel

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "eye.slash").font(.system(size: 21))
            Text("Agent details are hidden").font(.system(size: 14, weight: .semibold))
            Button("Show Agent Details") { model.settings.privacyMode = false }
        }
        .foregroundStyle(.white.opacity(0.8))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
