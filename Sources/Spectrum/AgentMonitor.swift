import Foundation
import SpectrumCore

/// Receives Claude Code hook events and keeps the model's session list current.
@MainActor
final class AgentMonitor {
    /// Sessions killed without a SessionEnd (closed terminal) disappear after this long.
    private static let staleAfter: TimeInterval = 60 * 60

    private let model: NotchModel
    private let server = AgentSocketServer(path: SpectrumPaths.agentSocket.path)
    private var store = SessionStore()
    private var pruneTimer: Timer?

    init(model: NotchModel) {
        self.model = model
    }

    func start() {
        do {
            try server.start { [weak self] payload in
                Task { @MainActor in self?.receive(payload) }
            }
        } catch {
            log.error("agent socket failed to start: \(error)")
        }
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.store.prune(inactiveFor: Self.staleAfter, now: Date())
                self.publish()
            }
        }
    }

    func stop() {
        server.stop()
    }

    private func receive(_ payload: Data) {
        do {
            store.apply(try AgentEvent.decode(payload), at: Date())
            publish()
        } catch {
            log.error("bad hook payload: \(error)")
        }
    }

    private func publish() {
        let ordered = store.ordered
        if model.sessions != ordered { model.sessions = ordered }
    }
}
