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
    private var waveform: AudioWaveformMonitor?
    private var agents: AgentMonitor?
    private var chats: ClaudeChatMonitor?
    private var transcripts: TranscriptMonitor?
    private var boss: BossMonitor?
    private var launcher: SessionLauncher?
    private var replies: ReplySender?
    private var settingsWindow: NSWindow?
    private var dismissal = HoverDismissal()
    private var shortcuts: ShortcutMonitor?
    private var hoverTimer: Timer?
    private var hoverRate: PointerPollRate?
    private var scrollMonitor: Any?
    private var swipe = SwipeDetector()

    private func configureHooks(for model: NotchModel) {
        let path = Bundle.main.executableURL?.resolvingSymlinksInPath().path
        for provider in AgentProvider.allCases {
            let url = provider.hooksURL
            if HookInstaller.isInstalled(settingsURL: url) {
                model.installedHooks.insert(provider)
            }
            if let path,
                HookInstaller.needsUpdate(
                    settingsURL: url, executablePath: path, provider: provider)
            {
                do {
                    try HookInstaller.install(
                        executablePath: path, settingsURL: url, provider: provider)
                } catch {
                    log.error("updating \(provider.name) hooks failed: \(error)")
                }
            }
        }
        model.onInstallHooks = { [weak model] provider in
            guard let path else { return }
            do {
                try HookInstaller.install(
                    executablePath: path, settingsURL: provider.hooksURL, provider: provider)
                model?.installedHooks.insert(provider)
            } catch {
                log.error("installing \(provider.name) hooks failed: \(error)")
                NSAlert(error: error).runModal()
            }
        }
        model.onRemoveHooks = { [weak model] provider in
            do {
                try HookInstaller.uninstall(settingsURL: provider.hooksURL)
                model?.installedHooks.remove(provider)
            } catch {
                log.error("removing \(provider.name) hooks failed: \(error)")
                NSAlert(error: error).runModal()
            }
        }
    }

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
        let model = NotchModel(geometry: geometry, settings: .load(from: .standard))
        configureHooks(for: model)
        model.onOpenSettings = { [weak self] in self?.showSettings() }
        model.onOpenChat = { _ in
            NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.anthropic.claudefordesktop"
            ).first?.activate()
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
                }
            NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
        }

        let nowPlaying = NowPlayingMonitor(model: model)
        let waveform = AudioWaveformMonitor(model: model)
        model.onWaveformActivity = { [weak waveform] active in waveform?.setActive(active) }
        model.onCommand = { [weak nowPlaying] in nowPlaying?.send($0) }
        nowPlaying.start()

        let agents = AgentMonitor(model: model)
        model.onPermission = { [weak agents] session, decision in
            agents?.answer(session, with: decision)
        }
        agents.start()
        let chats = ClaudeChatMonitor(model: model)
        chats.start()
        let transcripts = TranscriptMonitor(model: model)
        model.onTranscriptHook = { [weak transcripts] id in transcripts?.receivedHook(for: id) }
        let boss = BossMonitor(model: model)
        let launcher = SessionLauncher(model: model)
        model.onStartSession = { [weak launcher] directory, prompt in
            launcher?.start(in: directory, prompt: prompt)
        }
        model.onChooseFolder = { [weak launcher] in launcher?.chooseFolder() }
        model.onOpenTerminal = { [weak launcher] tab in launcher?.focus(tab) }
        let replies = ReplySender(model: model)
        model.onReply = { [weak replies] prompt, session in replies?.send(prompt, to: session) }

        let shortcuts = ShortcutMonitor(
            modifier: { [weak model] in model?.settings.shortcut ?? .doubleCommand },
            onDoubleTap: { [weak model] in model?.agentsOpen.toggle() },
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

        model.onModeChange = { [weak self] mode in
            self?.updatePointerTracking(for: mode, at: NSEvent.mouseLocation)
        }
        // Panel-only monitors sleep while it is closed instead of ticking to check.
        model.onPanelChange = { [weak chats, weak transcripts, weak boss] in
            chats?.tick()
            transcripts?.update()
            boss?.update()
        }

        self.panel = panel
        self.model = model
        self.nowPlaying = nowPlaying
        self.waveform = waveform
        self.agents = agents
        self.chats = chats
        self.transcripts = transcripts
        self.boss = boss
        self.launcher = launcher
        self.replies = replies
        self.shortcuts = shortcuts
    }

    func applicationWillTerminate(_ notification: Notification) {
        waveform?.setActive(false)
        agents?.stop()
    }

    /// While the island is hidden there is nothing to hover, so the pointer poll stops entirely
    /// and Spectrum stays asleep until music or the shortcut wakes it.
    private func updatePointerTracking(for mode: NotchMode, at pointer: CGPoint) {
        if mode == .hidden {
            hoverTimer?.invalidate()
            hoverTimer = nil
            hoverRate = nil
            tick(at: pointer)
            return
        }
        guard let model else { return }
        let rect = NotchLayout.visibleRect(
            for: mode, geometry: model.geometry, lyrics: model.lyrics != nil)
        let rate = PointerPollRate.resolve(pointer: pointer, island: rect, previous: hoverRate)
        guard hoverRate != rate else { return }
        hoverTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: rate.interval, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let pointer = NSEvent.mouseLocation
                self.tick(at: pointer)
                if let mode = self.model?.mode, mode != .hidden {
                    self.updatePointerTracking(for: mode, at: pointer)
                }
            }
        }
        timer.tolerance = rate.tolerance
        hoverTimer = timer
        hoverRate = rate
    }

    /// Polls the pointer instead of using tracking areas: the panel ignores mouse events while
    /// compact so clicks reach the menu bar underneath.
    private func tick(at pointer: CGPoint) {
        guard let model, let panel else { return }
        let rect = NotchLayout.visibleRect(
            for: model.mode, geometry: model.geometry, lyrics: model.lyrics != nil)
        let hovering = rect.insetBy(dx: -2, dy: -2).contains(pointer)
        if model.isHovering != hovering { model.isHovering = hovering }
        // A half-typed reply keeps the panel open even if the pointer drifts away.
        let open = model.mode == .agents && model.replyDraft.isEmpty
        if dismissal.update(isOpen: open, isInside: hovering) {
            model.agentsOpen = false
        }
        let interactive = [.expanded, .agents, .attention, .permission].contains(model.mode)
        if panel.ignoresMouseEvents == interactive { panel.ignoresMouseEvents = !interactive }
    }

    private func showSettings() {
        guard let model else { return }
        model.agentsOpen = false
        model.refreshLaunchAtLogin()
        if settingsWindow == nil {
            let window = NSWindow(
                contentViewController: NSHostingController(
                    rootView: SettingsView(model: model)))
            window.title = "Spectrum Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        // An accessory app has to activate itself for its window to take keyboard focus.
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
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
