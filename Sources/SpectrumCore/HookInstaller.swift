import Foundation

/// Adds and removes Spectrum's entries in Claude Code's `settings.json` without touching
/// anything else the user has configured there.
public enum HookInstaller {
    public enum InstallError: Error, Equatable {
        case settingsNotAnObject
    }

    /// Trailing shell comment that identifies Spectrum's hook commands.
    static let marker = "# spectrum"

    static let events: [AgentEvent.Kind] = [
        .sessionStart, .userPromptSubmit, .preToolUse, .postToolUse, .notification,
        .permissionRequest, .stop, .subagentStop, .sessionEnd,
    ]

    /// How long a permission hook waits for the island before Claude Code shows its own dialog.
    public static let permissionWait = 60

    public static func command(executablePath: String) -> String {
        let quoted = "'" + executablePath.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
        return "\(quoted) hook \(marker)"
    }

    public static func installing(into settings: [String: Any], command: String) -> [String: Any] {
        var result = removing(from: settings)
        var hooks = result["hooks"] as? [String: Any] ?? [:]
        for event in events {
            let timeout = event == .permissionRequest ? permissionWait + 15 : 5
            var group: [String: Any] = [
                "hooks": [["type": "command", "command": command, "timeout": timeout]]
            ]
            if [.preToolUse, .postToolUse, .permissionRequest].contains(event) {
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
    public static func install(executablePath: String, settingsURL: URL) throws {
        let settings = try readSettings(at: settingsURL)
        let backup = settingsURL.appendingPathExtension("spectrum-backup")
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: settingsURL.path),
            !fileManager.fileExists(atPath: backup.path)
        {
            try fileManager.copyItem(at: settingsURL, to: backup)
        }
        let updated = installing(into: settings, command: command(executablePath: executablePath))
        try writeSettings(updated, to: settingsURL)
    }

    public static func uninstall(settingsURL: URL) throws {
        let settings = try readSettings(at: settingsURL)
        try writeSettings(removing(from: settings), to: settingsURL)
    }

    /// True when Spectrum's hooks exist but don't match what this copy would install: they call
    /// a different executable (a development build vs. the installed app) or miss an event a
    /// newer version listens to.
    public static func needsUpdate(settingsURL: URL, executablePath: String) -> Bool {
        guard let data = try? Data(contentsOf: settingsURL) else { return false }
        guard String(decoding: data, as: UTF8.self).contains(marker) else { return false }
        // JSON escapes the quotes and slashes differently, so compare through a decode.
        guard let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let hooks = settings["hooks"] as? [String: Any]
        else { return false }
        let expected = command(executablePath: executablePath)
        func commands(_ value: Any?) -> [String] {
            ((value as? [[String: Any]]) ?? [])
                .compactMap { $0["hooks"] as? [[String: Any]] }.joined()
                .compactMap { $0["command"] as? String }
                .filter { $0.hasSuffix(marker) }
        }
        if hooks.values.flatMap(commands).contains(where: { $0 != expected }) { return true }
        return events.contains { commands(hooks[$0.rawValue]).isEmpty }
    }

    public static func isInstalled(settingsURL: URL) -> Bool {
        guard let data = try? Data(contentsOf: settingsURL) else { return false }
        return String(decoding: data, as: UTF8.self).contains(marker)
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
