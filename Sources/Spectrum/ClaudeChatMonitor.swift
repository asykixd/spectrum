import AppKit
import ApplicationServices
import IOKit.ps
import SpectrumCore

/// Reads the Claude desktop app's accessibility tree, off the main thread: a long chat has
/// thousands of nodes.
private final class ClaudeAppReader: @unchecked Sendable {
    static let bundleID = "com.anthropic.claudefordesktop"
    private static let nodeLimit = 6000

    private let queue = DispatchQueue(label: "spectrum.claude-app", qos: .utility)
    // Only touched on `queue`.
    private var enabledPID: pid_t?

    func snapshot() async -> ClaudeChatSnapshot? {
        guard
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
                .first
        else { return nil }
        let pid = app.processIdentifier
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.read(pid: pid))
            }
        }
    }

    private func read(pid: pid_t) -> ClaudeChatSnapshot? {
        let root = AXUIElementCreateApplication(pid)
        if enabledPID != pid {
            // Electron only builds its accessibility tree once a client asks for it.
            AXUIElementSetAttributeValue(
                root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            enabledPID = pid
        }
        var pageTitle: String?
        var url: URL?
        var buttons: [String] = []
        var texts: [String] = []
        var visited = 0

        func walk(_ element: AXUIElement) {
            visited += 1
            guard visited < Self.nodeLimit else { return }
            // One IPC round trip per node instead of one per attribute: this walk is the
            // most expensive thing Spectrum does.
            let node = attributes(of: element)
            switch node.role {
            case "AXWebArea":
                if let found = node.url, found.host() == "claude.ai" {
                    url = found
                    pageTitle = node.title
                }
            case kAXButtonRole:
                buttons += [node.description, node.title].compactMap { $0 }.filter { !$0.isEmpty }
            case kAXStaticTextRole:
                if let text = node.value, !text.isEmpty { texts.append(text) }
            default:
                break
            }
            node.children.forEach(walk)
        }

        let windows = value(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        windows.forEach(walk)
        guard url != nil else { return nil }
        return ClaudeChatSnapshot(
            pageTitle: pageTitle, url: url, buttonLabels: buttons, texts: texts)
    }

    private struct Node {
        var role: String?
        var title: String?
        var description: String?
        var value: String?
        var url: URL?
        var children: [AXUIElement] = []
    }

    private static let nodeAttributes = [
        kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, "AXURL",
        kAXChildrenAttribute,
    ]

    private func attributes(of element: AXUIElement) -> Node {
        var result: CFArray?
        guard
            AXUIElementCopyMultipleAttributeValues(
                element, Self.nodeAttributes as CFArray, [], &result)
                == .success,
            let values = result as? [AnyObject], values.count == 6
        else { return Node() }
        // Missing attributes come back as AXValue error placeholders, which the casts reject.
        return Node(
            role: values[0] as? String, title: values[1] as? String,
            description: values[2] as? String, value: values[3] as? String,
            url: values[4] as? URL, children: values[5] as? [AXUIElement] ?? [])
    }

    private func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var result: AnyObject?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        return status == .success ? result : nil
    }

}

/// Shows chats from the Claude desktop app as conversations in the office.
///
/// The app has no hooks, so Spectrum watches its UI through Accessibility: a Stop button means
/// Claude is answering, and the page title names the chat.
@MainActor
final class ClaudeChatMonitor {
    private let model: NotchModel
    private let reader = ClaudeAppReader()
    private var tracker = ClaudeChatTracker()
    private var timer: Timer?
    private var reading = false
    private var lastRead = Date.distantPast

    init(model: NotchModel) {
        self.model = model
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 0.3
    }

    private static var onBattery: Bool {
        let source = IOPSGetProvidingPowerSourceType(nil)?.takeRetainedValue() as String?
        return source == kIOPMBatteryPowerKey
    }

    private func refresh() {
        let frontmost =
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == ClaudeAppReader.bundleID
        guard !reading, model.settings.showClaudeChats,
            let interval = ChatPollPolicy.interval(
                panelOpen: model.agentsOpen, claudeFrontmost: frontmost,
                onBattery: Self.onBattery, pauseOnBattery: model.settings.pauseChatsOnBattery),
            Date().timeIntervalSince(lastRead) >= interval - 0.1, AXIsProcessTrusted()
        else { return }
        lastRead = Date()
        tracker.retention = TimeInterval(model.settings.chatRetentionMinutes * 60)
        reading = true
        Task {
            defer { reading = false }
            let snapshot = await reader.snapshot()
            let chats = tracker.update(snapshot, at: Date())
            if model.chatSessions != chats { model.chatSessions = chats }
        }
    }
}
