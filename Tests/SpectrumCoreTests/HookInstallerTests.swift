import Foundation
import Testing

@testable import SpectrumCore

private let command = HookInstaller.command(executablePath: "/Apps/Spectrum")

@Test func quotesExecutablePath() {
    #expect(
        HookInstaller.command(executablePath: "/a b/it's/Spectrum")
            == #"'/a b/it'\''s/Spectrum' hook # spectrum"#)
}

@Test func installAddsEveryEventAndKeepsUserHooks() throws {
    let userGroup: [String: Any] = ["hooks": [["type": "command", "command": "say hi"]]]
    let settings: [String: Any] = ["model": "opus", "hooks": ["Stop": [userGroup]]]

    let result = HookInstaller.installing(into: settings, command: command)

    #expect(result["model"] as? String == "opus")
    let hooks = try #require(result["hooks"] as? [String: Any])
    #expect(hooks.count == HookInstaller.events.count)
    let stop = try #require(hooks["Stop"] as? [[String: Any]])
    #expect(stop.count == 2)
    let pre = try #require(hooks["PreToolUse"] as? [[String: Any]])
    #expect(pre.first?["matcher"] as? String == "*")
}

@Test func installIsIdempotent() throws {
    let once = HookInstaller.installing(into: [:], command: command)
    let twice = HookInstaller.installing(into: once, command: command)

    let hooks = try #require(twice["hooks"] as? [String: Any])
    #expect((hooks["Stop"] as? [Any])?.count == 1)
}

@Test func removeRestoresOriginalSettings() throws {
    let userGroup: [String: Any] = ["hooks": [["type": "command", "command": "say hi"]]]
    let settings: [String: Any] = ["hooks": ["Stop": [userGroup]]]

    let restored = HookInstaller.removing(
        from: HookInstaller.installing(into: settings, command: command))

    let original = try JSONSerialization.data(withJSONObject: settings, options: .sortedKeys)
    let roundTrip = try JSONSerialization.data(withJSONObject: restored, options: .sortedKeys)
    #expect(original == roundTrip)
    #expect(
        HookInstaller.removing(from: HookInstaller.installing(into: [:], command: command)).isEmpty)
}

@Test func installWritesFileWithBackup() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: "settings.json")
    try Data(#"{"model":"opus"}"#.utf8).write(to: url)

    try HookInstaller.install(executablePath: "/Apps/Spectrum", settingsURL: url)

    #expect(HookInstaller.isInstalled(settingsURL: url))
    #expect(FileManager.default.fileExists(atPath: url.path + ".spectrum-backup"))
    try HookInstaller.uninstall(settingsURL: url)
    #expect(!HookInstaller.isInstalled(settingsURL: url))
}

@Test func rejectsNonObjectSettings() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("[1]".utf8).write(to: url)

    #expect(throws: HookInstaller.InstallError.settingsNotAnObject) {
        try HookInstaller.install(executablePath: "/x", settingsURL: url)
    }
}

@Test func detectsHooksFromAnotherCopy() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: "settings.json")

    try HookInstaller.install(executablePath: "/dev/build/Spectrum", settingsURL: url)

    #expect(
        HookInstaller.pointsElsewhere(
            settingsURL: url, executablePath: "/Applications/Spectrum.app/Contents/MacOS/Spectrum"))
    #expect(!HookInstaller.pointsElsewhere(settingsURL: url, executablePath: "/dev/build/Spectrum"))
}
