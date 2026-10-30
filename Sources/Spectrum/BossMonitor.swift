import Foundation
import SpectrumCore

/// Totals up Claude Code transcripts for the boss tab, only while that tab is on screen.
@MainActor
final class BossMonitor {
    private let model: NotchModel
    private var timer: Timer?
    private var scanner = UsageScanner(root: SpectrumPaths.claudeProjects)
    private var scanning = false
    /// Transcripts can hold hundreds of megabytes; a minute-old total is fresh enough.
    private let interval: TimeInterval = 60

    init(model: NotchModel) {
        self.model = model
    }

    /// Scans only while the boss tab is on screen; opening it shows fresh numbers right away.
    func update() {
        guard model.agentsOpen, model.tab == .boss else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
        timer?.tolerance = 10
    }

    private func scan() {
        guard !scanning else { return }
        scanning = true
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
