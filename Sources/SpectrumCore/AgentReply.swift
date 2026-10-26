import Foundation

/// Sending a prompt to a Claude Code session without its terminal: `claude -p --resume <id>`
/// continues the same session in the background, so the reply lands in its transcript.
public enum AgentReply {
    /// Places `claude` usually lives; a GUI app doesn't inherit the shell's PATH.
    public static let searchPaths = [
        "~/.local/bin", "~/.claude/local", "/opt/homebrew/bin", "/usr/local/bin",
    ]

    /// Replying while the agent works would run two turns on one session at once.
    public static func canReply(to session: AgentSession) -> Bool {
        session.kind == .code && !session.activity.isWorking
    }

    public static func arguments(sessionID: String, prompt: String) -> [String] {
        ["-p", "--resume", sessionID, prompt]
    }

    /// A login shell command that finds `claude` on the user's PATH plus the usual install
    /// locations, with session id and prompt passed as positional arguments, never interpolated.
    public static func shellScript(home: String) -> String {
        let extra = searchPaths.map { $0.replacingOccurrences(of: "~", with: home) }
        return #"PATH="\#(extra.joined(separator: ":")):$PATH" exec claude "$@""#
    }

    /// Trims and rejects empty prompts.
    public static func normalizedPrompt(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
