import Foundation
import Testing

@testable import SpectrumCore

private func session(_ id: String, updated: TimeInterval) -> AgentSession {
    AgentSession(
        id: id, cwd: nil, activity: .idle, startedAt: .distantPast,
        updatedAt: Date(timeIntervalSince1970: updated))
}

@Test func dismissedSessionStaysHiddenUntilItChanges() {
    var dismissals = Dismissals()
    dismissals.dismiss(session("a", updated: 10))

    let hidden = dismissals.visible([session("a", updated: 10), session("b", updated: 10)])
    let back = dismissals.visible([session("a", updated: 20)])

    #expect(hidden.map(\.id) == ["b"])
    #expect(back.map(\.id) == ["a"])
}

@Test func settingsRoundTripAndFillMissingKeys() throws {
    let defaults = try #require(UserDefaults(suiteName: "spectrum-test-\(UUID().uuidString)"))
    var settings = SpectrumSettings()
    settings.shortcut = .doubleOption
    settings.chatRetentionMinutes = 30
    try settings.save(to: defaults)

    #expect(SpectrumSettings.load(from: defaults) == settings)

    defaults.set(Data(#"{"haptics":false,"shortcut":"bogus"}"#.utf8), forKey: "settings")
    let partial = SpectrumSettings.load(from: defaults)
    #expect(!partial.haptics)
    #expect(partial.shortcut == .doubleCommand)
    #expect(partial.chatRetentionMinutes == 15)
}
