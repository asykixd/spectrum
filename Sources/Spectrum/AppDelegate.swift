import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }
        let panel = NotchPanel(screen: screen)
        panel.contentView = NSHostingView(
            rootView: NotchView(notchWidth: panel.geometry.notch.width))
        panel.orderFrontRegardless()
        self.panel = panel
    }
}
