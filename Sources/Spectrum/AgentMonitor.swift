import Foundation
import SpectrumCore

/// Receives coding agent hook events and keeps the model's session list current.
@MainActor
final class AgentMonitor {
    private let model: NotchModel
    private let server = AgentSocketServer(path: SpectrumPaths.agentSocket.path)
    private var store = SessionStore()
    private var pruneTimer: Timer?
    /// Permission hooks still waiting for an answer from the island, by session.
    private var pendingPermissions: [String: AgentSocketReply] = [:]

    init(model: NotchModel) {
        self.model = model
    }

    func start() {
        do {
            try server.start { [weak self] payload, reply in
                Task { @MainActor in
                    guard let self else { return reply.send(nil) }
                    self.receive(payload, reply: reply)
                }
            }
        } catch {
            log.error("agent socket failed to start: \(error)")
        }
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Sessions killed without a SessionEnd (closed terminal) disappear eventually.
                let staleAfter = TimeInterval(self.model.settings.staleAgentMinutes * 60)
                self.store.prune(inactiveFor: staleAfter, now: Date())
                self.publish()
            }
        }
        pruneTimer?.tolerance = 10
    }

    func stop() {
        for reply in pendingPermissions.values { reply.send(nil) }
        pendingPermissions = [:]
        server.stop()
    }

    /// Sends the island's answer to the waiting hook.
    func answer(_ session: AgentSession, with decision: PermissionDecision) {
        guard let reply = pendingPermissions.removeValue(forKey: session.id) else { return }
        reply.send(decision.hookOutput)
        store.answeredPermission(sessionID: session.id)
        publish()
    }

    private func receive(_ payload: Data, reply: AgentSocketReply) {
        let event: AgentEvent
        do {
            event = try AgentEvent.decode(payload)
        } catch {
            log.error("bad hook payload: \(error)")
            return reply.send(nil)
        }
        // Whatever the session does next, an older request of it can no longer be answered.
        pendingPermissions.removeValue(forKey: event.sessionKey)?.send(nil)
        store.apply(event, at: Date())
        if event.kind == .permissionRequest && model.settings.answerPermissions {
            wait(for: event.sessionKey, reply: reply)
        } else {
            reply.send(nil)
            store.expirePermission(sessionID: event.sessionKey)
        }
        publish()
    }

    private func wait(for sessionID: String, reply: AgentSocketReply) {
        pendingPermissions[sessionID] = reply
        // Give up a little before the hook does, so the island stops offering a dead answer.
        let deadline = TimeInterval(HookInstaller.permissionWait) - 2
        DispatchQueue.main.asyncAfter(deadline: .now() + deadline) { [weak self, weak reply] in
            MainActor.assumeIsolated {
                guard let self, let reply, self.pendingPermissions[sessionID] === reply else {
                    return
                }
                self.pendingPermissions[sessionID] = nil
                reply.send(nil)
                self.store.expirePermission(sessionID: sessionID)
                self.publish()
            }
        }
    }

    private func publish() {
        let ordered = store.ordered
        if model.codeSessions != ordered { model.codeSessions = ordered }
    }
}
