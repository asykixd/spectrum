import SpectrumCore
import SwiftUI

/// The boss's desk: what today's agent work took in time and money, project by project.
struct BossView: View {
    let report: BossReport?
    let dailyBudget: UsageBudget
    let windowBudget: UsageBudget

    var body: some View {
        if let report {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    spendTile(
                        "Spent today", cost: report.todayCost, budget: dailyBudget,
                        note: "at API prices")
                    tile("Tokens", value: tokens(report.todayTokens), note: "today")
                    tile("Agents worked", value: duration(report.activeTime), note: "today")
                    if let window = report.window {
                        spendTile(
                            "5-hour window", cost: window.cost, budget: windowBudget,
                            note: "resets \(window.end.formatted(date: .omitted, time: .shortened))"
                        )
                    } else {
                        tile(
                            "5-hour window", value: "—",
                            note: windowBudget.limit > 0
                                ? "Limit \(money(windowBudget.limit))"
                                : "starts with the next prompt")
                    }
                }
                if report.projects.isEmpty {
                    Text("No Claude Code work today yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ViewThatFits(in: .vertical) {
                        rows(report).frame(maxHeight: .infinity, alignment: .top)
                        ScrollView { rows(report) }.scrollIndicators(.never)
                    }
                }
            }
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func rows(_ report: BossReport) -> some View {
        let top = report.projects.map(\.cost).max() ?? 0
        return VStack(spacing: 6) {
            ForEach(report.projects) { project in
                ProjectRow(project: project, share: top > 0 ? project.cost / top : 0)
            }
        }
    }

    private func spendTile(_ title: String, cost: Double, budget: UsageBudget, note: String)
        -> some View
    {
        let reached = budget.reached(by: cost)
        let caption =
            reached ? "Limit reached" : budget.limit > 0 ? "Limit \(money(budget.limit))" : note
        return tile(title, value: money(cost), note: caption, highlighted: reached)
            .help(budget.limit > 0 ? "Estimated API cost · limit \(money(budget.limit))" : note)
    }

    private func tile(_ title: String, value: String, note: String, highlighted: Bool = false)
        -> some View
    {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundStyle(highlighted ? Color(hex: 0xF5B544) : .white)
            Text(note)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.06)))
    }
}

private struct ProjectRow: View {
    let project: BossReport.Project
    /// Cost relative to the most expensive project, for the bar behind the row.
    let share: Double

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(project.sessions == 1 ? "1 session" : "\(project.sessions) sessions")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
                if let prompt = project.lastPrompt {
                    Text(prompt)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            Text(duration(project.activeTime))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 60, alignment: .trailing)
            Text(money(project.cost))
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color(hex: 0x4ADE80))
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(alignment: .leading) {
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: 0x4ADE80).opacity(0.08))
                    .frame(width: proxy.size.width * share)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.05)))
    }
}

private func money(_ dollars: Double) -> String {
    dollars.formatted(.currency(code: "USD").precision(.fractionLength(2)))
}

private func tokens(_ count: Int) -> String {
    switch count {
    case 1_000_000...: String(format: "%.1fM", Double(count) / 1_000_000)
    case 1_000...: String(format: "%.0fK", Double(count) / 1_000)
    default: "\(count)"
    }
}

private func duration(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds / 60)
    return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
}
