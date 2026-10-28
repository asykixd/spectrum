import Foundation

public enum SpectrumPaths {
    public static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Spectrum", directoryHint: .isDirectory)
    }

    /// Unix socket the app listens on for Claude Code hook events.
    public static var agentSocket: URL {
        supportDirectory.appending(path: "agent.sock")
    }

    /// Claude Code's transcripts, one folder per project.
    public static var claudeProjects: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(
            path: ".claude/projects", directoryHint: .isDirectory)
    }

    public static var claudeSettings: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/settings.json")
    }
}
