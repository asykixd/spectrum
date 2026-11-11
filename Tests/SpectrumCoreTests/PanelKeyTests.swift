import Testing

@testable import SpectrumCore

@Test func sessionArrowsFollowListOrderWithoutWrapping() {
    let ids = ["first", "second", "third"]
    #expect(PanelKey.down.move(in: ids, from: nil) == "first")
    #expect(PanelKey.up.move(in: ids, from: "gone") == "third")
    #expect(PanelKey.down.move(in: ids, from: "first") == "second")
    #expect(PanelKey.down.move(in: ids, from: "third") == "third")
    #expect(PanelKey.up.move(in: ids, from: "first") == "first")
    #expect(PanelKey.enter.move(in: ids, from: "first") == nil)
}

@Test func keyboardCanOnlyAllowOnceOrDeny() {
    if case .allow? = PanelKey.enter.permissionDecision {
    } else {
        Issue.record("Return did not allow once")
    }
    if case .deny? = PanelKey.escape.permissionDecision {
    } else {
        Issue.record("Escape did not deny")
    }
    #expect(PanelKey.down.permissionDecision == nil)
}
