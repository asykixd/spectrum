import SpectrumCore
import SwiftUI

/// Opened with ⌘⌘: who is doing what, as a list or as an office.
struct AgentsPanelView: View {
    @Bindable var model: NotchModel

    private var waiting: Int { model.sessions.filter { $0.activity == .waitingForUser }.count }
    private var working: Int { model.sessions.filter { $0.activity.isWorking }.count }

    var body: some View {
        VStack(spacing: 0) {
            // Header lives on the ears around the hardware notch.
            HStack(spacing: 0) {
                TabSwitcher(tab: $model.tab, count: model.sessions.count)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: model.geometry.notch.width)
                StatusSummary(working: working, waiting: waiting)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .frame(height: max(model.geometry.notch.height, 32))

            Group {
                switch model.tab {
                case .sessions:
                    SessionsListView(
                        sessions: model.sessions, hooksInstalled: model.hooksInstalled,
                        installHooks: model.onInstallHooks)
                case .office:
                    OfficeView(sessions: model.sessions)
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
    @Binding var tab: AgentsTab
    let count: Int

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
            withAnimation(.snappy(duration: 0.2)) { tab = value }
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

struct SessionsListView: View {
    let sessions: [AgentSession]
    let hooksInstalled: Bool
    let installHooks: () -> Void

    var body: some View {
        if sessions.isEmpty {
            emptyState
        } else {
            // Scroll only when the rows don't fit, so a short list sits still like a widget.
            ViewThatFits(in: .vertical) {
                rows.frame(maxHeight: .infinity, alignment: .top)
                ScrollView { rows }.scrollIndicators(.never)
            }
        }
    }

    private var rows: some View {
        VStack(spacing: 6) {
            ForEach(sessions) { SessionRow(session: $0) }
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
            if hooksInstalled {
                Text("Start a Claude Code session and it shows up here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                Text("Spectrum listens to Claude Code through hooks.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                Button(action: installHooks) {
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

    private var isWaiting: Bool { session.activity == .waitingForUser }

    var body: some View {
        HStack(spacing: 12) {
            AgentAvatar(session: session)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.projectName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    StatusDot(activity: session.activity)
                    Text(session.activity.summary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isWaiting ? Color(hex: 0xF5B544) : .white.opacity(0.6))
                }
            }
            .lineLimit(1)
            Spacer()
            if let cwd = session.cwd {
                Text(abbreviated(cwd))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: 220, alignment: .trailing)
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(elapsed(since: session.updatedAt, now: timeline.date))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isWaiting ? Color(hex: 0xF59E0B, opacity: 0.14) : .white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isWaiting ? Color(hex: 0xF59E0B, opacity: 0.5) : .clear)
        )
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

private struct StatusDot: View {
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
        case .thinking: Color(hex: 0x60A5FA)
        case .waitingForUser: Color(hex: 0xF59E0B)
        case .idle, .finished: .white.opacity(0.35)
        }
    }
}
