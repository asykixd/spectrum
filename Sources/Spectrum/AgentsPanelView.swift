import SpectrumCore
import SwiftUI

/// Opened with a double tap: who is doing what, as a list or as an office.
struct AgentsPanelView: View {
    let model: NotchModel

    private var working: Int { model.sessions.filter { $0.activity.isWorking }.count }

    var body: some View {
        VStack(spacing: 0) {
            // Header lives on the ears around the hardware notch.
            HStack(spacing: 0) {
                TabSwitcher(tab: model.tab, count: model.sessions.count, select: model.select)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: model.geometry.notch.width)
                HStack(spacing: 12) {
                    StatusSummary(working: working, waiting: model.waitingCount)
                    Button(action: model.openNewSession) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("New Claude Code session")
                    PanelMenu(model: model)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .frame(height: max(model.geometry.notch.height, 32))

            Group {
                switch model.tab {
                case .sessions:
                    if let session = model.selectedSession {
                        ConversationView(model: model, session: session)
                    } else if model.newSessionOpen {
                        NewSessionView(model: model)
                    } else {
                        SessionsListView(model: model)
                    }
                case .office:
                    OfficeView(model: model)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                case .boss:
                    BossView(
                        report: model.bossReport,
                        dailyBudget: UsageBudget(model.settings.dailySpendLimit),
                        windowBudget: UsageBudget(model.settings.windowSpendLimit))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }
}

private struct TabSwitcher: View {
    let tab: AgentsTab
    let count: Int
    let select: (AgentsTab) -> Void

    var body: some View {
        HStack(spacing: 4) {
            item(
                .sessions, title: count > 0 ? "Sessions \(count)" : "Sessions",
                symbol: "list.bullet")
            item(.office, title: "Office", symbol: "building.2")
            item(.boss, title: "Boss", symbol: "briefcase")
        }
        .padding(3)
        .background(Capsule().fill(.white.opacity(0.08)))
    }

    /// Three tabs don't fit the ear beside the notch with titles, so only the open one has a
    /// title; the others show their icon (and the session count).
    private func item(_ value: AgentsTab, title: String, symbol: String) -> some View {
        let selected = tab == value
        return Button {
            withAnimation(.snappy(duration: 0.2)) { select(value) }
        } label: {
            Group {
                if selected {
                    Label(title, systemImage: symbol)
                } else if value == .sessions, count > 0 {
                    Label("\(count)", systemImage: symbol)
                } else {
                    Image(systemName: symbol)
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(selected ? .black : .white.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(selected ? .white : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct StatusSummary: View {
    let working: Int
    let waiting: Int

    var body: some View {
        HStack(spacing: 10) {
            if waiting > 0 {
                badge("\(waiting) waiting", color: Color(hex: 0xF59E0B))
            }
            badge("\(working) working", color: Color(hex: 0x4ADE80))
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.75))
    }
}

/// Settings, hooks and quitting: Spectrum has no Dock icon or menu bar item.
private struct PanelMenu: View {
    let model: NotchModel

    var body: some View {
        if model.renderingStill {
            icon
        } else {
            menu
        }
    }

    private var icon: some View {
        Image(systemName: "gearshape.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.7))
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
    }

    private var menu: some View {
        Menu {
            Button("Settings…", action: model.onOpenSettings)
            Button("Hide Agent Details") { model.settings.privacyMode = true }
            Divider()
            ForEach(AgentProvider.allCases, id: \.self) { provider in
                if model.installedHooks.contains(provider) {
                    Button("Remove \(provider.name) Hooks") { model.onRemoveHooks(provider) }
                } else {
                    Button("Install \(provider.name) Hooks") { model.onInstallHooks(provider) }
                }
            }
            Divider()
            Button("Quit Spectrum") { NSApp.terminate(nil) }
        } label: {
            icon
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct SessionsListView: View {
    let model: NotchModel

    private var groups: SessionGroups { SessionGroups(model.sessions) }

    var body: some View {
        if model.sessions.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if let error = model.terminalError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: 0xF5B544))
                }
                // Scroll only when the rows don't fit, so a short list sits still like a widget.
                ScrollViewReader { proxy in
                    ViewThatFits(in: .vertical) {
                        sections.frame(maxHeight: .infinity, alignment: .top)
                        ScrollView { sections }.scrollIndicators(.never)
                    }
                    .onChange(of: model.keyboardSessionID) { _, id in
                        if let id { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(AgentProvider.allCases, id: \.self) { provider in
                section(
                    provider.name, symbol: "terminal",
                    sessions: groups.code(for: provider))
            }
            section("Chats", symbol: "bubble.left.and.bubble.right", sessions: groups.chats)
            section("AFK", symbol: "moon.zzz", sessions: groups.afk)
        }
    }

    @ViewBuilder
    private func section(_ title: String, symbol: String, sessions: [AgentSession]) -> some View {
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("\(title) · \(sessions.count)", systemImage: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.leading, 4)
                ForEach(sessions) { session in
                    SessionRow(
                        session: session, style: model.settings.characters,
                        hovering: model.hoveredSessionID == session.id,
                        keyboardSelected: model.keyboardSessionID == session.id,
                        cost: session.kind == .code && session.provider == .claude
                            ? model.bossReport?.sessionCosts[session.id] : nil,
                        hover: { inside in
                            if inside {
                                model.hoveredSessionID = session.id
                            } else if model.hoveredSessionID == session.id {
                                model.hoveredSessionID = nil
                            }
                        },
                        open: { model.open(session) },
                        openTerminal: {
                            if let tab = session.terminalTab { model.onOpenTerminal(tab) }
                        },
                        dismiss: { withAnimation(.snappy) { model.dismiss(session) } }
                    )
                    .id(session.id)
                }
            }
        }
    }

    private var emptyStateHint: String {
        if model.installedHooks.contains(.codex) {
            return "Trust Spectrum’s hooks in Codex, then start a session."
        }
        if model.installedHooks.contains(.claude) {
            return "Start a Claude Code session or a chat in the Claude app."
        }
        return "Install hooks to see sessions from Claude Code or Codex."
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.5))
            Text("No agents running")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text(emptyStateHint)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
            HStack {
                ForEach(AgentProvider.allCases, id: \.self) { provider in
                    if !model.installedHooks.contains(provider) {
                        Button {
                            model.onInstallHooks(provider)
                        } label: {
                            Text("Install \(provider.name) hooks")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(.white))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SessionRow: View {
    let session: AgentSession
    let style: SpectrumSettings.CharacterStyle
    let hovering: Bool
    let keyboardSelected: Bool
    let cost: Double?
    let hover: (Bool) -> Void
    let open: () -> Void
    let openTerminal: () -> Void
    let dismiss: () -> Void

    private var isWaiting: Bool { session.activity == .waitingForUser }

    var body: some View {
        HStack(spacing: 12) {
            AgentAvatar(session: session, style: style)
                .overlay {
                    if !session.tasks.isEmpty { TaskRing(fraction: session.tasks.fraction) }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(session.projectName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    StatusDot(activity: session.activity)
                    Text(session.statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isWaiting ? Color(hex: 0xF5B544) : .white.opacity(0.6))
                    if session.provider == .codex {
                        Text(session.provider.name)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    if !session.tasks.isEmpty {
                        Text(taskSummary)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    if !session.changes.isEmpty {
                        ChangeCounts(changes: session.changes)
                    }
                }
            }
            .lineLimit(1)
            Spacer()
            if let cost {
                Text(cost.formatted(.currency(code: "USD").precision(.fractionLength(2))))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .help("Today's estimated API cost")
            }
            if let place = session.kind == .chat ? "Claude app" : session.cwd.map(abbreviated) {
                Text(place)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: 200, alignment: .trailing)
            }
            if hovering {
                if session.terminalTab != nil {
                    Button(action: openTerminal) {
                        Image(systemName: "terminal")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .help("Open in Terminal")
                    .accessibilityLabel("Open in Terminal")
                }
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("Remove from the list until it does something new")
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text(elapsed(since: session.updatedAt, now: timeline.date))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 22, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    isWaiting
                        ? Color(hex: 0xF59E0B, opacity: 0.14)
                        : .white.opacity(hovering ? 0.1 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    keyboardSelected
                        ? .white.opacity(0.72)
                        : isWaiting ? Color(hex: 0xF59E0B, opacity: 0.5) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: open)
        .onHover(perform: hover)
        .contextMenu {
            Button(session.kind == .chat ? "Open in Claude" : "Show Conversation", action: open)
            if session.terminalTab != nil { Button("Open in Terminal", action: openTerminal) }
            Button("Remove from List", action: dismiss)
        }
    }

    private var taskSummary: String {
        let tasks = session.tasks
        let count = "\(tasks.completed)/\(tasks.total)"
        return tasks.current.map { "· \(count) \($0)" } ?? "· \(count)"
    }

    private func abbreviated(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func elapsed(since date: Date, now: Date) -> String {
        let seconds = max(Int(now.timeIntervalSince(date)), 0)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }
}

/// "· 3 files +120 −14" for what the agent changed since the last prompt.
private struct ChangeCounts: View {
    let changes: ChangeSummary

    var body: some View {
        HStack(spacing: 4) {
            Text(changes.files == 1 ? "· 1 file" : "· \(changes.files) files")
                .foregroundStyle(.white.opacity(0.4))
            Text("+\(changes.added)").foregroundStyle(Color(hex: 0x4ADE80, opacity: 0.8))
            Text("−\(changes.removed)").foregroundStyle(Color(hex: 0xF87171, opacity: 0.8))
        }
        .font(.system(size: 11).monospacedDigit())
    }
}

/// How much of its plan an agent has done, drawn around its avatar.
private struct TaskRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.1), lineWidth: 2)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color(hex: 0x4ADE80), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(-3)
    }
}

struct StatusDot: View {
    let activity: AgentActivity

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !activity.isWorking)) {
            timeline in
            let pulse =
                activity.isWorking
                ? 0.55 + 0.45 * abs(sin(timeline.date.timeIntervalSinceReferenceDate * 3)) : 1
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .opacity(pulse)
        }
    }

    private var color: Color {
        switch activity {
        case .usingTool: Color(hex: 0x4ADE80)
        case .responding: ClaudeLook.orange
        case .thinking: Color(hex: 0x60A5FA)
        case .waitingForUser: Color(hex: 0xF59E0B)
        case .idle, .finished: .white.opacity(0.35)
        }
    }
}
