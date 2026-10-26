import SpectrumCore
import SwiftUI

/// Opened with a double tap: who is doing what, as a list or as an office.
struct AgentsPanelView: View {
    let model: NotchModel

    private var waiting: Int { model.sessions.filter { $0.activity == .waitingForUser }.count }
    private var working: Int { model.sessions.filter { $0.activity.isWorking }.count }

    var body: some View {
        VStack(spacing: 0) {
            // Header lives on the ears around the hardware notch.
            HStack(spacing: 0) {
                TabSwitcher(tab: model.tab, count: model.sessions.count, select: model.select)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: model.geometry.notch.width)
                HStack(spacing: 12) {
                    StatusSummary(working: working, waiting: waiting)
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
                    } else {
                        SessionsListView(model: model)
                    }
                case .office:
                    OfficeView(model: model)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        }
        .padding(3)
        .background(Capsule().fill(.white.opacity(0.08)))
    }

    private func item(_ value: AgentsTab, title: String, symbol: String) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { select(value) }
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tab == value ? .black : .white.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(tab == value ? .white : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
        Menu {
            Button("Settings…", action: model.onOpenSettings)
            Divider()
            if model.hooksInstalled {
                Button("Remove Claude Code Hooks", action: model.onRemoveHooks)
            } else {
                Button("Install Claude Code Hooks", action: model.onInstallHooks)
            }
            Divider()
            Button("Quit Spectrum") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
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
            // Scroll only when the rows don't fit, so a short list sits still like a widget.
            ViewThatFits(in: .vertical) {
                sections.frame(maxHeight: .infinity, alignment: .top)
                ScrollView { sections }.scrollIndicators(.never)
            }
        }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("Claude Code", symbol: "terminal", sessions: groups.code)
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
                        hover: { inside in
                            if inside {
                                model.hoveredSessionID = session.id
                            } else if model.hoveredSessionID == session.id {
                                model.hoveredSessionID = nil
                            }
                        },
                        open: { model.open(session) },
                        dismiss: { withAnimation(.snappy) { model.dismiss(session) } })
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.5))
            Text("No agents running")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            if model.hooksInstalled {
                Text("Start a Claude Code session or a chat in the Claude app.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                Text("Spectrum listens to Claude Code through hooks.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                Button(action: model.onInstallHooks) {
                    Text("Install Claude Code hooks")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SessionRow: View {
    let session: AgentSession
    let style: SpectrumSettings.CharacterStyle
    let hovering: Bool
    let hover: (Bool) -> Void
    let open: () -> Void
    let dismiss: () -> Void

    private var isWaiting: Bool { session.activity == .waitingForUser }

    var body: some View {
        HStack(spacing: 12) {
            AgentAvatar(session: session, style: style)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.projectName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    StatusDot(activity: session.activity)
                    Text(session.statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isWaiting ? Color(hex: 0xF5B544) : .white.opacity(0.6))
                }
            }
            .lineLimit(1)
            Spacer()
            if let place = session.kind == .chat ? "Claude app" : session.cwd.map(abbreviated) {
                Text(place)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: 200, alignment: .trailing)
            }
            if hovering {
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
                .strokeBorder(isWaiting ? Color(hex: 0xF59E0B, opacity: 0.5) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: open)
        .onHover(perform: hover)
        .contextMenu {
            Button(session.kind == .chat ? "Open in Claude" : "Show Conversation", action: open)
            Button("Remove from List", action: dismiss)
        }
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
