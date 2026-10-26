import SpectrumCore
import SwiftUI

struct NotchRootView: View {
    let model: NotchModel

    private var mode: NotchMode { model.mode }
    private var size: CGSize { NotchLayout.size(for: mode, geometry: model.geometry) }
    private var shape: UnevenRoundedRectangle {
        let radius = NotchLayout.bottomRadius(for: mode)
        return UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape.fill(.black)
            content
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .shadow(
            color: .black.opacity(mode == .hidden || mode == .compact ? 0 : 0.35), radius: 18, y: 8
        )
        // Without a hardware notch the hidden island would be a visible black pill.
        .opacity(mode == .hidden && !model.geometry.hasHardwareNotch ? 0 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: mode)
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
            AgentsPanelView(model: model)
        }
    }
}
