import Foundation

/// A Claude Code permission request, reduced to what fits on the island.
public struct PermissionPrompt: Equatable, Sendable {
    public var tool: String
    /// The command, file or URL the tool would touch, when the input names one.
    public var detail: String?

    public init(tool: String, detail: String?) {
        self.tool = tool
        self.detail = detail
    }
}

/// The user's answer from the island, sent back to the waiting `PermissionRequest` hook.
public enum PermissionDecision: Sendable {
    case allow
    case deny

    /// JSON for the hook's stdout, in the shape Claude Code reads a decision from.
    public var hookOutput: Data {
        var decision: [String: Any] = [:]
        switch self {
        case .allow:
            decision["behavior"] = "allow"
        case .deny:
            decision["behavior"] = "deny"
            decision["message"] = "The user denied this from Spectrum."
        }
        let output: [String: Any] = [
            "hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]
        ]
        // Only strings and nested dictionaries: serialization can't fail.
        return (try? JSONSerialization.data(withJSONObject: output, options: .sortedKeys)) ?? Data()
    }
}
