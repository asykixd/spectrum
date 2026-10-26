import AppKit
import SpectrumCore

/// Borderless panel pinned over the notch, above the menu bar.
final class NotchPanel: NSPanel {
    let geometry: NotchGeometry

    init(screen: NSScreen) {
        geometry = NotchGeometry(
            screenFrame: screen.frame,
            topLeftArea: screen.auxiliaryTopLeftArea,
            topRightArea: screen.auxiliaryTopRightArea
        )
        super.init(
            contentRect: geometry.panel,
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
