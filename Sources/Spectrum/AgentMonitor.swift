import Foundation
import SpectrumCore

/// Receives coding agent hook events and keeps the model's session list current.
@MainActor
final class AgentMonitor {
    private struct PendingPermission {
        let id: UUID
        let reply: AgentSocketReply
        let projectRule: ProjectPermissionRule?
    }

    private let model: NotchModel
    private let server = AgentSocketServer(path: SpectrumPaths.agentSocket.path)
    private var store = SessionStore()
    private var pruneTimer: Timer?
    /// Permission hooks still waiting for an answer from the island, by session.
    private var pendingPermissions: [String: PendingPermission] = [:]

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
        releasePermissions()
        server.stop()
    }

    func releasePermissions() {
        for (id, pending) in pendingPermissions {
            pending.reply.send(nil)
            store.expirePermission(sessionID: id)
        }
        pendingPermissions.removeAll()
        publish()
    }

    /// Sends the island's answer to the waiting hook.
    func answer(sessionID: String, requestID: UUID, with decision: PermissionDecision) {
        guard let pending = pendingPermissions[sessionID], pending.id == requestID else { return }
        if case .alwaysAllow(let rule) = decision, rule != pending.projectRule { return }
        pendingPermissions.removeValue(forKey: sessionID)
        pending.reply.send(decision.hookOutput)
        store.answeredPermission(sessionID: sessionID)
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
        // Claude emits a notification about the same prompt while its permission hook waits.
        if event.kind == .notification, pendingPermissions[event.sessionKey] != nil {
            return reply.send(nil)
        }
        pendingPermissions.removeValue(forKey: event.sessionKey)?.reply.send(nil)
        let requestID =
            event.kind == .permissionRequest && event.provider.supportsPermissionHooks
                && model.settings.answerPermissions
                && !model.settings.privacyMode
            ? UUID() : nil
        store.apply(event, at: Date(), permissionID: requestID)
        if let requestID {
            wait(
                for: event.sessionKey,
                pending: PendingPermission(
                    id: requestID, reply: reply,
                    projectRule: store.sessions[event.sessionKey]?.permission?.projectRule))
        } else {
            reply.send(nil)
            store.expirePermission(sessionID: event.sessionKey)
        }
        publish()
        model.onTranscriptHook(event.sessionKey)
    }

    private func wait(for sessionID: String, pending: PendingPermission) {
        pendingPermissions[sessionID] = pending
        let requestID = pending.id
        // Give up a little before the hook does, so the island stops offering a dead answer.
        let deadline = TimeInterval(HookInstaller.permissionWait) - 2
        DispatchQueue.main.asyncAfter(deadline: .now() + deadline) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let pending = self.pendingPermissions[sessionID],
                    pending.id == requestID
                else { return }
                self.pendingPermissions[sessionID] = nil
                pending.reply.send(nil)
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
