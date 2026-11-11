import Foundation

public enum AgentProvider: String, CaseIterable, Decodable, Sendable {
    case claude
    case codex
    case cursor
    case copilot

    public var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .copilot: "GitHub Copilot"
        }
    }

    public var hooksURL: URL {
        switch self {
        case .claude: SpectrumPaths.claudeSettings
        case .codex: SpectrumPaths.codexHooks
        case .cursor: SpectrumPaths.cursorHooks
        case .copilot: SpectrumPaths.copilotHooks
        }
    }

    public var supportsTranscript: Bool { self == .claude || self == .codex }
    public var supportsPermissionHooks: Bool { self == .claude || self == .codex }

    var usesFlatHooks: Bool { self == .cursor || self == .copilot }
}
