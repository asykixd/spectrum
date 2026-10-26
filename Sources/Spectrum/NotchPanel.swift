import AppKit

/// Borderless panel pinned over the notch, above the menu bar.
final class NotchPanel: NSPanel {
    private static let size = NSSize(width: 220, height: 32)

    init(screen: NSScreen) {
        let frame = NSRect(
            x: screen.frame.midX - Self.size.width / 2,
            y: screen.frame.maxY - Self.size.height,
            width: Self.size.width,
            height: Self.size.height
        )
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
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }
}
