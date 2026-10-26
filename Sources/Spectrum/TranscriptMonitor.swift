import Foundation
import SpectrumCore

/// Keeps the open conversation in the sessions tab in sync with its transcript file.
@MainActor
final class TranscriptMonitor {
    private let model: NotchModel
    private var timer: Timer?
    private var loading = false

    init(model: NotchModel) {
        self.model = model
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        guard !loading, model.agentsOpen, let session = model.selectedSession,
            let path = session.transcriptPath
        else { return }
        loading = true
        let id = session.id
        Task {
            defer { loading = false }
            let messages = await Task.detached(priority: .utility) {
                do {
                    return try Transcript.load(from: URL(fileURLWithPath: path))
                } catch {
                    log.error("reading transcript failed: \(error)")
                    return []
                }
            }.value
            // The user may have opened another session meanwhile.
            guard model.selectedSessionID == id, model.transcript != messages else { return }
            model.transcript = messages
        }
    }
}
