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
        didSet {
            guard selectedSessionID != oldValue else { return }
            transcript = []
            replyError = nil
        }
    }
    var transcript: [TranscriptMessage] = []
    var replyDraft = ""
    var replyError: String?
    /// Sessions with a `claude -p --resume` run in flight.
    var replyingSessionIDs: Set<String> = []
    /// Row under the pointer in the sessions list; it reveals the remove button.
    var hoveredSessionID: String?
    /// Agent under the pointer in the office.
    var officeHoverID: String?

    var agentsOpen = false {
        didSet {
            if agentsOpen { attention.acknowledge() }
            updateMode()
        }
    }
    @ObservationIgnored private var attention = AttentionTracker()
    /// What the island is calling the user about, if anything.
    private(set) var signal: AttentionTracker.Signal?
    var isHovering = false { didSet { updateMode() } }
    var tab: AgentsTab = .sessions
    var hooksInstalled = false

    private(set) var mode: NotchMode = .hidden

    @ObservationIgnored var onCommand: (MediaCommand) -> Void = { _ in }
    @ObservationIgnored var onInstallHooks: () -> Void = {}
    @ObservationIgnored var onRemoveHooks: () -> Void = {}
    @ObservationIgnored var onOpenSettings: () -> Void = {}
    @ObservationIgnored var onOpenChat: (AgentSession) -> Void = { _ in }
    @ObservationIgnored var onReply: (String, AgentSession) -> Void = { _, _ in }
    @ObservationIgnored var onHaptic: (HapticCue) -> Void = { _ in }
    @ObservationIgnored var onModeChange: (NotchMode) -> Void = { _ in }
    /// Fixed time for the office's day/night cycle; only the preview command sets it.
    @ObservationIgnored var clockOverride: Date?
    /// Set by the preview command: `ImageRenderer` can't draw AppKit-backed controls such as
    /// menus and text fields, so views swap in static stand-ins.
    @ObservationIgnored var renderingStill = false

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

    /// Opens a session's conversation; from the office this jumps to the sessions tab.
    func open(_ session: AgentSession, fromOffice: Bool = false) {
        switch session.kind {
        case .code:
            selectedSessionID = session.id
            if fromOffice { tab = .sessions }
        case .chat:
            onOpenChat(session)
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
        attention.update(visible, now: Date())
        if agentsOpen { attention.acknowledge() }
        if let until = attention.doneUntil, until > Date() {
            // Re-evaluate once the checkmark has had its moment.
            DispatchQueue.main.asyncAfter(deadline: .now() + until.timeIntervalSinceNow + 0.05) {
                [weak self] in
                self?.updateMode()
            }
        }
        updateMode()
    }

    /// Clicking the pulsing island opens the panel on the agent that asked.
    func answerAttention() {
        if case .needsYou(let session) = signal {
            tab = .sessions
            selectedSessionID = session.id
        }
        agentsOpen = true
    }

    private func updateMode() {
        let track = settings.showMusic ? nowPlaying : nil
        var current = attention.signal(at: Date())
        switch current {
        case .needsYou where !settings.alertWhenNeeded, .done where !settings.flashWhenDone:
            current = nil
        default:
            break
        }
        if current != signal { signal = current }
        let next = NotchMode.resolve(
            current: mode,
            isPlaying: track?.isPlaying ?? false,
            hasTrack: track != nil,
            isHovering: isHovering,
            agentsOpen: agentsOpen,
            signal: current
        )
        guard next != mode else { return }
        if settings.haptics, let cue = HapticCue.forTransition(from: mode, to: next) {
            onHaptic(cue)
        }
        mode = next
        onModeChange(next)
    }
}

/// Sizes of the black island in each mode.
enum NotchLayout {
    static let expandedSize = CGSize(width: 440, height: 128)
    static let agentsSize = CGSize(width: 680, height: 340)
    /// Each ear is wide enough for an agent's name next to the hardware notch.
    static let signalEarWidth: CGFloat = 110

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
        case .attention, .done:
            return CGSize(width: notch.width + signalEarWidth * 2, height: notch.height)
        }
    }

    static func bottomRadius(for mode: NotchMode) -> CGFloat {
        switch mode {
        case .hidden, .compact, .attention, .done: 10
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
