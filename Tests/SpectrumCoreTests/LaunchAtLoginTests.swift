import ServiceManagement
import Testing

@testable import SpectrumCore

@Test func launchAtLoginUsesTheSystemRegistrationState() {
    #expect(LaunchAtLogin(.notRegistered) == .off)
    #expect(LaunchAtLogin(.enabled) == .on)
    #expect(LaunchAtLogin(.requiresApproval) == .needsApproval)
    #expect(LaunchAtLogin(.notFound) == .unavailable)
}

@Test func launchAtLoginOnlyChangesARegistrationWhenNeeded() {
    #expect(LaunchAtLogin.off.change(to: true) == .register)
    #expect(LaunchAtLogin.off.change(to: false) == nil)
    #expect(LaunchAtLogin.on.change(to: true) == nil)
    #expect(LaunchAtLogin.on.change(to: false) == .unregister)
    #expect(LaunchAtLogin.unavailable.change(to: true) == nil)
    #expect(LaunchAtLogin.unavailable.change(to: false) == nil)
}

@Test func pendingLoginItemApprovalCanBeCancelled() {
    let pending = LaunchAtLogin(.requiresApproval)
    #expect(pending.isRequested)
    #expect(pending.change(to: false) == .unregister)
    #expect(pending.change(to: true) == nil)
}
