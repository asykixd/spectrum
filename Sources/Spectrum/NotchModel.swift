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

    var settings: SpectrumSettings {
        didSet {
            guard settings != oldValue else { return }
            do {
                try settings.save(to: .standard)
            } catch {
                log.error("saving settings failed: \(error)")
            }
            refreshSessions()
            updateMode()
        }
    }

    var nowPlaying: NowPlaying? { didSet { updateMode() } }
    var artwork: NSImage?
    var accent: Color = .white

    var codeSessions: [AgentSession] = [] { didSet { refreshSessions() } }
    var chatSessions: [AgentSession] = [] { didSet { refreshSessions() } }
    /// What the panel shows: chats first, without the ones the user removed.
    private(set) var sessions: [AgentSession] = []
    @ObservationIgnored private var dismissals = Dismissals()

    /// Code session whose conversation is open in the sessions tab.
    var selectedSessionID: String? {
        didSet { if selectedSessionID != oldValue { transcript = [] } }
    }
    var transcript: [TranscriptMessage] = []
    /// Row under the pointer in the sessions list; it reveals the remove button.
    var hoveredSessionID: String?

    var agentsOpen = false { didSet { updateMode() } }
    var isHovering = false { didSet { updateMode() } }
    var tab: AgentsTab = .sessions
    var hooksInstalled = false

    private(set) var mode: NotchMode = .hidden

    @ObservationIgnored var onCommand: (MediaCommand) -> Void = { _ in }
    @ObservationIgnored var onInstallHooks: () -> Void = {}
    @ObservationIgnored var onRemoveHooks: () -> Void = {}
    @ObservationIgnored var onOpenSettings: () -> Void = {}
    @ObservationIgnored var onOpenChat: (AgentSession) -> Void = { _ in }
    @ObservationIgnored var onHaptic: (HapticCue) -> Void = { _ in }

    init(geometry: NotchGeometry, settings: SpectrumSettings = SpectrumSettings()) {
        self.geometry = geometry
        self.settings = settings
    }

    var selectedSession: AgentSession? {
        sessions.first { $0.id == selectedSessionID }
    }

    /// Player controls stay silent on the trackpad: haptics there felt noisy.
    func perform(_ command: MediaCommand) {
        onCommand(command)
    }

    func select(_ newTab: AgentsTab) {
        tab = newTab
    }

    func open(_ session: AgentSession) {
        switch session.kind {
        case .code: selectedSessionID = session.id
        case .chat: onOpenChat(session)
        }
    }

    func dismiss(_ session: AgentSession) {
        dismissals.dismiss(session)
        if selectedSessionID == session.id { selectedSessionID = nil }
        refreshSessions()
    }

    private func refreshSessions() {
        let chats = settings.showClaudeChats ? chatSessions : []
        let visible = dismissals.visible(chats + codeSessions)
        if visible != sessions { sessions = visible }
    }

    private func updateMode() {
        let track = settings.showMusic ? nowPlaying : nil
        let next = NotchMode.resolve(
            current: mode,
            isPlaying: track?.isPlaying ?? false,
            hasTrack: track != nil,
            isHovering: isHovering,
            agentsOpen: agentsOpen
        )
        guard next != mode else { return }
        if settings.haptics, let cue = HapticCue.forTransition(from: mode, to: next) {
            onHaptic(cue)
        }
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
