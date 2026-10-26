import AppKit
import Observation
import SpectrumCore
import SwiftUI

enum AgentsTab: Hashable {
    case sessions
    case office
}

/// Single source of truth for everything the notch shows.
@MainActor
@Observable
final class NotchModel {
    let geometry: NotchGeometry

    var nowPlaying: NowPlaying? { didSet { updateMode() } }
    var artwork: NSImage?
    var accent: Color = .white
    var codeSessions: [AgentSession] = []
    var chatSessions: [AgentSession] = []
    /// Chats first: they are the conversations the user is most likely looking at.
    var sessions: [AgentSession] { chatSessions + codeSessions }
    var agentsOpen = false { didSet { updateMode() } }
    var isHovering = false { didSet { updateMode() } }
    var tab: AgentsTab = .sessions
    var hooksInstalled = false

    private(set) var mode: NotchMode = .hidden

    @ObservationIgnored var onCommand: (MediaCommand) -> Void = { _ in }
    @ObservationIgnored var onInstallHooks: () -> Void = {}
    @ObservationIgnored var onHaptic: (HapticCue) -> Void = { _ in }

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    /// Player controls stay silent on the trackpad: haptics there felt noisy.
    func perform(_ command: MediaCommand) {
        onCommand(command)
    }

    func select(_ newTab: AgentsTab) {
        tab = newTab
    }

    private func updateMode() {
        let next = NotchMode.resolve(
            current: mode,
            isPlaying: nowPlaying?.isPlaying ?? false,
            hasTrack: nowPlaying != nil,
            isHovering: isHovering,
            agentsOpen: agentsOpen
        )
        guard next != mode else { return }
        if let cue = HapticCue.forTransition(from: mode, to: next) { onHaptic(cue) }
        mode = next
    }
}

/// Sizes of the black island in each mode.
enum NotchLayout {
    static let expandedSize = CGSize(width: 440, height: 128)
    static let agentsSize = CGSize(width: 680, height: 340)

    static func size(for mode: NotchMode, geometry: NotchGeometry) -> CGSize {
        let notch = geometry.notch.size
        switch mode {
        case .hidden: return notch
        case .compact: return geometry.panel.size
        case .expanded:
            return CGSize(
                width: expandedSize.width, height: notch.height + expandedSize.height)
        case .agents:
            return CGSize(width: agentsSize.width, height: notch.height + agentsSize.height)
        }
    }

    static func bottomRadius(for mode: NotchMode) -> CGFloat {
        switch mode {
        case .hidden, .compact: 10
        case .expanded: 28
        case .agents: 32
        }
    }

    /// Room for the largest mode; the window itself never resizes, only its content.
    static func panelFrame(for geometry: NotchGeometry) -> CGRect {
        let largest = size(for: .agents, geometry: geometry)
        let width = largest.width + 40
        let height = largest.height + 20
        return CGRect(
            x: geometry.notch.midX - width / 2, y: geometry.notch.maxY - height,
            width: width, height: height)
    }

    /// Visible island in screen coordinates.
    static func visibleRect(for mode: NotchMode, geometry: NotchGeometry) -> CGRect {
        let size = size(for: mode, geometry: geometry)
        return CGRect(
            x: geometry.notch.midX - size.width / 2, y: geometry.notch.maxY - size.height,
            width: size.width, height: size.height)
    }
}
