import Foundation

/// An agent permission request, reduced to what fits on the island.
public struct PermissionPrompt: Equatable, Sendable {
    public var tool: String
    /// The command, file or URL the tool would touch, when the input names one.
    public var detail: String?
    public var requestID: UUID?
    public var projectRule: ProjectPermissionRule?

    public init(
        tool: String, detail: String?, requestID: UUID? = nil,
        projectRule: ProjectPermissionRule? = nil
    ) {
        self.tool = tool
        self.detail = detail
        self.requestID = requestID
        self.projectRule = projectRule
    }
}

public struct ProjectPermissionRule: Equatable, Sendable {
    public let command: String

    init?(tool: String, command: String) {
        // Keep the saved rule literal and short enough to show in full on the island.
        let literal = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ._/-:=+,@%"
            .utf8
        guard tool == "Bash", (1...80).contains(command.utf8.count),
            command.utf8.allSatisfy({ literal.contains($0) }),
            command.trimmingCharacters(in: .whitespaces) == command
        else { return nil }
        self.command = command
    }
}

/// The user's answer from the island, sent back to the waiting `PermissionRequest` hook.
public enum PermissionDecision: Sendable {
    case allow
    case alwaysAllow(ProjectPermissionRule)
    case deny

    /// JSON for the hook's stdout, in the shape the agent reads a decision from.
    public var hookOutput: Data {
        var decision: [String: Any] = [:]
        switch self {
        case .allow:
            decision["behavior"] = "allow"
        case .alwaysAllow(let rule):
            decision["behavior"] = "allow"
            decision["updatedPermissions"] = [
                [
                    "type": "addRules", "behavior": "allow", "destination": "localSettings",
                    "rules": [["toolName": "Bash", "ruleContent": rule.command]],
                ]
            ]
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
