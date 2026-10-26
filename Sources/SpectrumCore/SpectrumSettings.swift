import Foundation

/// User preferences, stored as JSON in UserDefaults.
public struct SpectrumSettings: Codable, Equatable, Sendable {
    public enum Shortcut: String, Codable, CaseIterable, Sendable {
        case doubleCommand
        case doubleOption
        case doubleControl
    }

    public enum CharacterStyle: String, Codable, CaseIterable, Sendable {
        /// The Claude Code mascot, one accessory per agent.
        case clawd
        case people
    }

    public var showMusic = true
    public var showClaudeChats = true
    /// How long a Claude app chat stays listed after it was last open.
    public var chatRetentionMinutes = 15
    public var shortcut: Shortcut = .doubleCommand
    public var haptics = true
    /// Code agents that stay quiet this long leave the office without a SessionEnd.
    public var staleAgentMinutes = 60
    /// Lets the conversation view send prompts to idle Claude Code sessions.
    public var replyFromPanel = true
    public var characters: CharacterStyle = .clawd
    /// Stops reading the Claude app on battery unless the agents panel is open.
    public var pauseChatsOnBattery = true
    /// Pulse the island while a Claude Code agent waits for permission or an answer.
    public var alertWhenNeeded = true
    /// Flash a checkmark when a task finishes.
    public var flashWhenDone = true

    public init() {}

    /// Missing keys fall back to defaults, so adding a setting never resets the others.
    public init(from decoder: Decoder) throws {
        let defaults = SpectrumSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showMusic =
            try container.decodeIfPresent(Bool.self, forKey: .showMusic) ?? defaults.showMusic
        showClaudeChats =
            try container.decodeIfPresent(Bool.self, forKey: .showClaudeChats)
            ?? defaults.showClaudeChats
        chatRetentionMinutes =
            try container.decodeIfPresent(Int.self, forKey: .chatRetentionMinutes)
            ?? defaults.chatRetentionMinutes
        shortcut =
            (try? container.decodeIfPresent(Shortcut.self, forKey: .shortcut)) ?? defaults.shortcut
        haptics = try container.decodeIfPresent(Bool.self, forKey: .haptics) ?? defaults.haptics
        staleAgentMinutes =
            try container.decodeIfPresent(Int.self, forKey: .staleAgentMinutes)
            ?? defaults.staleAgentMinutes
        replyFromPanel =
            try container.decodeIfPresent(Bool.self, forKey: .replyFromPanel)
            ?? defaults.replyFromPanel
        characters =
            (try? container.decodeIfPresent(CharacterStyle.self, forKey: .characters))
            ?? defaults.characters
        pauseChatsOnBattery =
            try container.decodeIfPresent(Bool.self, forKey: .pauseChatsOnBattery)
            ?? defaults.pauseChatsOnBattery
        alertWhenNeeded =
            try container.decodeIfPresent(Bool.self, forKey: .alertWhenNeeded)
            ?? defaults.alertWhenNeeded
        flashWhenDone =
            try container.decodeIfPresent(Bool.self, forKey: .flashWhenDone)
            ?? defaults.flashWhenDone
    }

    public static func load(from defaults: UserDefaults, key: String = "settings")
        -> SpectrumSettings
    {
        guard let data = defaults.data(forKey: key),
            let settings = try? JSONDecoder().decode(SpectrumSettings.self, from: data)
        else { return SpectrumSettings() }
        return settings
    }

    public func save(to defaults: UserDefaults, key: String = "settings") throws {
        defaults.set(try JSONEncoder().encode(self), forKey: key)
    }
}
