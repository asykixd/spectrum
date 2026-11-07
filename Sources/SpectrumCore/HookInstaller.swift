import Foundation

/// Adds and removes Spectrum's entries in an agent's JSON hook configuration.
public enum HookInstaller {
    public enum InstallError: Error, Equatable {
        case settingsNotAnObject
        case invalidHooks
    }

    /// Trailing shell comment that identifies Spectrum's hook commands.
    static let marker = "# spectrum"

    static let events: [AgentEvent.Kind] = [
        .sessionStart, .userPromptSubmit, .preToolUse, .postToolUse, .notification,
        .permissionRequest, .stop, .subagentStop, .sessionEnd,
    ]

    private static let codexEvents: [AgentEvent.Kind] = [
        .sessionStart, .userPromptSubmit, .preToolUse, .postToolUse, .permissionRequest,
        .stop, .interrupt, .sessionEnd,
    ]

    private static func events(for provider: AgentProvider) -> [AgentEvent.Kind] {
        provider == .codex ? codexEvents : events
    }

    /// How long a permission hook waits for the island before the agent shows its own dialog.
    public static let permissionWait = 60

    public static func command(executablePath: String, provider: AgentProvider = .claude) -> String
    {
        let quoted = "'" + executablePath.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
        let arguments = provider == .codex ? "hook codex" : "hook"
        return "\(quoted) \(arguments) \(marker)"
    }

    public static func installing(
        into settings: [String: Any], command: String, provider: AgentProvider = .claude
    ) -> [String: Any] {
        var result = removing(from: settings)
        var hooks = result["hooks"] as? [String: Any] ?? [:]
        for event in events(for: provider) {
            let timeout: Int
            switch event {
            case .permissionRequest: timeout = permissionWait + 15
            case .interrupt where provider == .codex, .sessionEnd where provider == .codex:
                timeout = 3
            default: timeout = 5
            }
            var group: [String: Any] = [
                "hooks": [["type": "command", "command": command, "timeout": timeout]]
            ]
            if provider == .claude, [.preToolUse, .postToolUse, .permissionRequest].contains(event)
            {
                group["matcher"] = "*"
            }
            var groups = hooks[event.rawValue] as? [Any] ?? []
            groups.append(group)
            hooks[event.rawValue] = groups
        }
        result["hooks"] = hooks
        return result
    }

    public static func removing(from settings: [String: Any]) -> [String: Any] {
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        for (event, value) in hooks {
            guard let groups = value as? [Any] else { continue }
            let kept = groups.compactMap { group -> Any? in
                guard var dict = group as? [String: Any], let entries = dict["hooks"] as? [Any]
                else { return group }
                let remaining = entries.filter { !isSpectrumEntry($0) }
                if remaining.count == entries.count { return group }
                if remaining.isEmpty { return nil }
                dict["hooks"] = remaining
                return dict
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        var result = settings
        result["hooks"] = hooks.isEmpty ? nil : hooks
        return result
    }

    /// Installs hooks into the settings file, keeping a one-time backup of the original.
    public static func install(
        executablePath: String, settingsURL: URL, provider: AgentProvider = .claude
    ) throws {
        let settings = try readSettings(at: settingsURL)
        if let hooks = settings["hooks"] {
            guard hooks is [String: [[String: Any]]]
            else { throw InstallError.invalidHooks }
        }
        let backup = settingsURL.appendingPathExtension("spectrum-backup")
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: settingsURL.path),
            !fileManager.fileExists(atPath: backup.path)
        {
            try fileManager.copyItem(at: settingsURL, to: backup)
        }
        let updated = installing(
            into: settings, command: command(executablePath: executablePath, provider: provider),
            provider: provider)
        try writeSettings(updated, to: settingsURL)
    }

    public static func uninstall(settingsURL: URL) throws {
        let settings = try readSettings(at: settingsURL)
        guard hasSpectrumHooks(in: settings) else { return }
        try writeSettings(removing(from: settings), to: settingsURL)
    }

    /// True when Spectrum's hooks exist but don't match what this copy would install: they call
    /// a different executable (a development build vs. the installed app) or miss an event a
    /// newer version listens to.
    public static func needsUpdate(
        settingsURL: URL, executablePath: String, provider: AgentProvider = .claude
    ) -> Bool {
        guard let settings = try? readSettings(at: settingsURL),
            let hooks = settings["hooks"] as? [String: [[String: Any]]]
        else { return false }
        let expected = command(executablePath: executablePath, provider: provider)
        func commands(_ groups: [[String: Any]]) -> [String] {
            groups
                .compactMap { $0["hooks"] as? [[String: Any]] }.joined()
                .compactMap { $0["command"] as? String }
                .filter { $0.hasSuffix(marker) }
        }
        let installed = hooks.mapValues(commands)
        let allCommands = installed.values.joined()
        guard !allCommands.isEmpty else { return false }
        return allCommands.contains { $0 != expected }
            || events(for: provider).contains { installed[$0.rawValue]?.count != 1 }
    }

    public static func isInstalled(settingsURL: URL) -> Bool {
        guard let settings = try? readSettings(at: settingsURL) else { return false }
        return hasSpectrumHooks(in: settings)
    }

    private static func hasSpectrumHooks(in settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: [[String: Any]]] else { return false }
        return hooks.values.joined().contains { group in
            (group["hooks"] as? [Any])?.contains(where: isSpectrumEntry) == true
        }
    }

    private static func isSpectrumEntry(_ entry: Any) -> Bool {
        guard let command = (entry as? [String: Any])?["command"] as? String else { return false }
        return command.hasSuffix(marker)
    }

    private static func readSettings(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.settingsNotAnObject
        }
        return object
    }

    private static func writeSettings(_ settings: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }
}
