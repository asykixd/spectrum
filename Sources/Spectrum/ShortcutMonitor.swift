import AppKit
import SpectrumCore

/// Watches the keyboard system-wide for ⌘⌘ and Esc, and mouse clicks for click-outside.
@MainActor
final class ShortcutMonitor {
    private static let escapeKeyCode: UInt16 = 53

    private let onDoubleCommand: () -> Void
    private let onEscape: () -> Void
    private let onClick: (CGPoint) -> Void
    private var detector = DoubleTapDetector()
    private var commandDown = false
    private var monitors: [Any] = []

    init(
        onDoubleCommand: @escaping () -> Void, onEscape: @escaping () -> Void,
        onClick: @escaping (CGPoint) -> Void
    ) {
        self.onDoubleCommand = onDoubleCommand
        self.onEscape = onEscape
        self.onClick = onClick
    }

    func start() {
        let keys: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        let handle: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: keys.union(clicks), handler: handle)
        {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: keys.union(clicks),
            handler: { event in
                handle(event)
                return event
            })
        {
            monitors.append(local)
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            onClick(NSEvent.mouseLocation)
        case .keyDown:
            _ = detector.handle(.other, at: event.timestamp)
            if event.keyCode == Self.escapeKeyCode { onEscape() }
        case .flagsChanged:
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let input: DoubleTapDetector.Input
            if flags == .command, !commandDown {
                commandDown = true
                input = .modifierDown
            } else if flags.isEmpty, commandDown {
                commandDown = false
                input = .modifierUp
            } else {
                commandDown = flags.contains(.command)
                input = .other
            }
            if detector.handle(input, at: event.timestamp) { onDoubleCommand() }
        default:
            break
        }
    }
}
