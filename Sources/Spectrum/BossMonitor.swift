import Foundation
import SpectrumCore

/// Totals up Claude Code transcripts for the boss tab, only while that tab is on screen.
@MainActor
final class BossMonitor {
    private let model: NotchModel
    private var timer: Timer?
    private var scanner = UsageScanner(root: SpectrumPaths.claudeProjects)
    private var scanning = false
    private var lastScan: Date?
    /// Transcripts can hold hundreds of megabytes; a minute-old total is fresh enough.
    private let interval: TimeInterval = 60

    init(model: NotchModel) {
        self.model = model
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 0.5
    }

    private func tick() {
        let visible = model.agentsOpen && model.tab == .boss
        guard visible else {
            // Next time the tab opens it shows fresh numbers right away.
            lastScan = nil
            return
        }
        guard !scanning, lastScan.map({ Date().timeIntervalSince($0) >= interval }) ?? true
        else { return }
        scanning = true
        lastScan = Date()
        let scanner = self.scanner
        Task {
            let now = Date()
            // The five-hour window can reach into yesterday evening.
            let since = Calendar.current.startOfDay(for: now)
                .addingTimeInterval(-BossReport.windowLength)
            let (updated, report) = await Task.detached(priority: .utility) {
                var scanner = scanner
                let log = scanner.scan(since: since)
                return (scanner, BossReport(log: log, now: now))
            }.value
            self.scanner = updated
            model.bossReport = report
            scanning = false
        }
    }
}
