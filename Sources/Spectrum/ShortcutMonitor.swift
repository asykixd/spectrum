import AppKit
import SpectrumCore

/// Watches the keyboard system-wide for the double-tap shortcut and Esc, and mouse clicks for
/// click-outside.
@MainActor
final class ShortcutMonitor {
    private static let escapeKeyCode: UInt16 = 53

    private let modifier: () -> SpectrumSettings.Shortcut
    private let onDoubleTap: () -> Void
    private let onEscape: () -> Void
    private let onClick: (CGPoint) -> Void
    private var detector = DoubleTapDetector()
    private var modifierDown = false
    private var lastInputCount: UInt32 = 0
    private var monitors: [Any] = []

    init(
        modifier: @escaping () -> SpectrumSettings.Shortcut, onDoubleTap: @escaping () -> Void,
        onEscape: @escaping () -> Void, onClick: @escaping (CGPoint) -> Void
    ) {
        self.modifier = modifier
        self.onDoubleTap = onDoubleTap
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
            _ = detector.handle(.other, at: event.timestamp)
            onClick(NSEvent.mouseLocation)
        case .keyDown:
            _ = detector.handle(.other, at: event.timestamp)
            if event.keyCode == Self.escapeKeyCode { onEscape() }
        case .flagsChanged:
            if Self.inputCount() != lastInputCount {
                lastInputCount = Self.inputCount()
                _ = detector.handle(.other, at: event.timestamp)
            }
            let key: NSEvent.ModifierFlags =
                switch modifier() {
                case .doubleCommand: .command
                case .doubleOption: .option
                case .doubleControl: .control
                }
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let input: DoubleTapDetector.Input
            if flags == key, !modifierDown {
                modifierDown = true
                input = .modifierDown
            } else if flags.isEmpty, modifierDown {
                modifierDown = false
                input = .modifierUp
            } else {
                modifierDown = flags.contains(key)
                input = .other
            }
            if detector.handle(input, at: event.timestamp) { onDoubleTap() }
        default:
            break
        }
    }

    /// System-wide count of key presses, clicks and scrolls. The global monitor misses keyDown
    /// without Accessibility or under Secure Keyboard Entry (Terminal, password fields), and
    /// never sees scrolls; these counters still tick, so ⌘C ⌘V or ⌘-scroll can't fake a tap.
    private static func inputCount() -> UInt32 {
        let types: [CGEventType] = [
            .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel,
        ]
        return types.reduce(0) {
            $0 &+ CGEventSource.counterForEventType(.combinedSessionState, eventType: $1)
        }
    }
}
