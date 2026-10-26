import AppKit
import ApplicationServices
import OSLog
import SpectrumCore
import SwiftUI

let log = Logger(subsystem: "dev.spectrum", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel?
    private var model: NotchModel?
    private var nowPlaying: NowPlayingMonitor?
    private var agents: AgentMonitor?
    private var shortcuts: ShortcutMonitor?
    private var hoverTimer: Timer?
    private var scrollMonitor: Any?
    private var swipe = SwipeDetector()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        guard let screen else {
            log.error("no screen available")
            return
        }
        let geometry = NotchGeometry(
            screenFrame: screen.frame,
            topLeftArea: screen.auxiliaryTopLeftArea,
            topRightArea: screen.auxiliaryTopRightArea
        )
        let model = NotchModel(geometry: geometry)
        model.hooksInstalled = HookInstaller.isInstalled(settingsURL: SpectrumPaths.claudeSettings)
        model.onInstallHooks = { [weak model] in
            guard let path = Bundle.main.executableURL?.resolvingSymlinksInPath().path else {
                return
            }
            do {
                try HookInstaller.install(
                    executablePath: path, settingsURL: SpectrumPaths.claudeSettings)
                model?.hooksInstalled = true
            } catch {
                log.error("hook install failed: \(error)")
            }
        }

        let panel = NotchPanel(frame: NotchLayout.panelFrame(for: geometry))
        panel.contentView = NSHostingView(rootView: NotchRootView(model: model))
        panel.orderFrontRegardless()

        // Felt only on Force Touch trackpads, and only while a finger is on them.
        model.onHaptic = { cue in
            let pattern: NSHapticFeedbackManager.FeedbackPattern =
                switch cue {
                case .expand: .levelChange
                case .collapse: .alignment
                case .tap: .generic
                }
            NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
        }

        let nowPlaying = NowPlayingMonitor(model: model)
        model.onCommand = { [weak nowPlaying] in nowPlaying?.send($0) }
        nowPlaying.start()

        let agents = AgentMonitor(model: model)
        agents.start()

        let shortcuts = ShortcutMonitor(
            onDoubleCommand: { [weak model] in model?.agentsOpen.toggle() },
            onEscape: { [weak model] in model?.agentsOpen = false },
            onClick: { [weak model] location in
                guard let model, model.agentsOpen else { return }
                let visible = NotchLayout.visibleRect(for: .agents, geometry: model.geometry)
                if !visible.contains(location) { model.agentsOpen = false }
            }
        )
        shortcuts.start()
        requestAccessibilityIfNeeded()
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
            [weak self] event in
            MainActor.assumeIsolated { self?.handleScroll(event) }
            return event
        }

        hoverTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }

        self.panel = panel
        self.model = model
        self.nowPlaying = nowPlaying
        self.agents = agents
        self.shortcuts = shortcuts
    }

    func applicationWillTerminate(_ notification: Notification) {
        agents?.stop()
    }

    /// Polls the pointer instead of using tracking areas: the panel ignores mouse events while
    /// compact so clicks reach the menu bar underneath.
    private func tick() {
        guard let model, let panel else { return }
        let rect = NotchLayout.visibleRect(for: model.mode, geometry: model.geometry)
        let hovering = rect.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
        if model.isHovering != hovering { model.isHovering = hovering }
        let interactive = model.mode == .expanded || model.mode == .agents
        if panel.ignoresMouseEvents == interactive { panel.ignoresMouseEvents = !interactive }
    }

    /// Two-finger swipe across the expanded player changes the track, like flicking a card.
    private func handleScroll(_ event: NSEvent) {
        guard let model, model.mode == .expanded, event.momentumPhase.isEmpty else { return }
        let phase: SwipeDetector.Phase
        if event.phase.contains(.began) {
            phase = .began
        } else if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            phase = .ended
        } else if event.phase.contains(.changed) {
            phase = .changed
        } else {
            return
        }
        // With natural scrolling the deltas follow the content, not the fingers.
        let sign = event.isDirectionInvertedFromDevice ? 1.0 : -1.0
        let direction = swipe.handle(
            deltaX: sign * event.scrollingDeltaX, deltaY: event.scrollingDeltaY, phase: phase)
        switch direction {
        case .left: model.perform(.nextTrack)
        case .right: model.perform(.previousTrack)
        case nil: break
        }
    }

    /// Global ⌘ and Esc monitoring needs Accessibility; macOS shows its own prompt once.
    private func requestAccessibilityIfNeeded() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        if !AXIsProcessTrustedWithOptions([key: true] as CFDictionary) {
            log.notice("waiting for Accessibility permission for the ⌘⌘ shortcut")
        }
    }
}
