import Foundation

public enum SpectrumPaths {
    public static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Spectrum", directoryHint: .isDirectory)
    }

    /// Unix socket the app listens on for agent hook events.
    public static var agentSocket: URL {
        supportDirectory.appending(path: "agent.sock")
    }

    public static var usageCache: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Caches/dev.spectrum/usage.plist")
    }

    public static var mediaCache: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Caches/dev.spectrum/media", directoryHint: .isDirectory)
    }

    /// Claude Code's transcripts, one folder per project.
    public static var claudeProjects: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(
            path: ".claude/projects", directoryHint: .isDirectory)
    }

    public static var codexHooks: URL {
        if let home = ProcessInfo.processInfo.environment["CODEX_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home, isDirectory: true).appending(path: "hooks.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/hooks.json")
    }

    public static var claudeSettings: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/settings.json")
    }

    public static var cursorHooks: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".cursor/hooks.json")
    }

    public static var copilotHooks: URL {
        if let home = ProcessInfo.processInfo.environment["COPILOT_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home, isDirectory: true).appending(
                path: "hooks/spectrum.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(
            path: ".copilot/hooks/spectrum.json")
    }
}
