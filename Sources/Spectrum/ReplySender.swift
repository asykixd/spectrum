import Foundation
import SpectrumCore

/// Runs `claude -p --resume` for replies typed in the conversation view.
@MainActor
final class ReplySender {
    private let model: NotchModel

    init(model: NotchModel) {
        self.model = model
    }

    func send(_ prompt: String, to session: AgentSession) {
        guard AgentReply.canReply(to: session), !model.replyingSessionIDs.contains(session.id)
        else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // A login shell picks up the user's PATH; arguments go through "$@", never into the
        // script text, so the prompt can contain anything.
        process.arguments =
            ["-lc", AgentReply.shellScript(home: NSHomeDirectory()), "spectrum-reply"]
            + AgentReply.arguments(sessionID: session.id, prompt: prompt)
        if let cwd = session.cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        let errors = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice

        let id = session.id
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            let stderr = String(
                decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            Task { @MainActor in self?.finish(id: id, status: status, stderr: stderr) }
        }
        do {
            try process.run()
            model.replyingSessionIDs.insert(id)
            model.replyError = nil
            model.replyDraft = ""
        } catch {
            model.replyError = "Couldn't start claude: \(error.localizedDescription)"
        }
    }

    private func finish(id: String, status: Int32, stderr: String) {
        model.replyingSessionIDs.remove(id)
        guard status != 0 else { return }
        let reason = stderr.split(separator: "\n").last.map(String.init) ?? "exit code \(status)"
        log.error("reply to \(id) failed: \(stderr)")
        if model.selectedSessionID == id { model.replyError = reason }
    }
}
