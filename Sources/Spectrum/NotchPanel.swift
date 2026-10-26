import AppKit
import SpectrumCore

/// Borderless panel pinned over the notch, above the menu bar.
final class NotchPanel: NSPanel {
    init(frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Above .mainMenu so the panel can sit on top of the menu bar around the notch.
        level = .mainMenu + 1
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }

    // Lets SwiftUI controls (tabs, scrolling) work without activating the app.
    override var canBecomeKey: Bool { true }
}
