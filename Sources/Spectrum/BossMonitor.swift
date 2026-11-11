import Foundation
import SpectrumCore

/// Totals up Claude Code transcripts for the Boss tab and visible session costs.
@MainActor
final class BossMonitor {
    private let model: NotchModel
    private var timer: Timer?
    private var scanner = UsageScanner(
        root: SpectrumPaths.claudeProjects, cacheURL: SpectrumPaths.usageCache)
    private var scanning = false
    /// Transcripts can hold hundreds of megabytes; a minute-old total is fresh enough.
    private let interval: TimeInterval = 60

    init(model: NotchModel) {
        self.model = model
    }

    /// Scans only while the panel is showing a cost.
    func update() {
        let showsSessions =
            model.tab == .sessions && model.selectedSessionID == nil
            && !model.newSessionOpen
            && model.sessions.contains { $0.kind == .code && $0.provider == .claude }
        guard model.agentsOpen, !model.settings.privacyMode, model.tab == .boss || showsSessions
        else {
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
            let baseline: UsageScanner
            if model.bossReport == nil {
                let (restored, cached) = await Task.detached(priority: .utility) {
                    var scanner = scanner
                    let report = scanner.cachedLog(since: since).map {
                        BossReport(log: $0, now: now)
                    }
                    return (scanner, report)
                }.value
                if let cached { model.bossReport = cached }
                baseline = restored
            } else {
                baseline = scanner
            }
            let (updated, report) = await Task.detached(priority: .utility) {
                var scanner = baseline
                let log = scanner.scan(since: since)
                return (scanner, BossReport(log: log, now: now))
            }.value
            self.scanner = updated
            model.bossReport = report
            scanning = false
        }
    }
}
