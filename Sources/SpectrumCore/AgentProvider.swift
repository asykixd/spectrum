import Foundation

public enum AgentProvider: String, CaseIterable, Decodable, Sendable {
    case claude
    case codex

    public var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    public var hooksURL: URL {
        switch self {
        case .claude: SpectrumPaths.claudeSettings
        case .codex: SpectrumPaths.codexHooks
        }
    }
}
