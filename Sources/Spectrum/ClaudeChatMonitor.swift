import AppKit
import ApplicationServices
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
            switch string(element, kAXRoleAttribute) {
            case "AXWebArea":
                if let found = value(element, "AXURL") as? URL, found.host() == "claude.ai" {
                    url = found
                    pageTitle = string(element, kAXTitleAttribute)
                }
            case kAXButtonRole:
                for attribute in [kAXDescriptionAttribute, kAXTitleAttribute] {
                    if let label = string(element, attribute), !label.isEmpty {
                        buttons.append(label)
                    }
                }
            case kAXStaticTextRole:
                if let text = string(element, kAXValueAttribute), !text.isEmpty {
                    texts.append(text)
                }
            default:
                break
            }
            for child in value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                walk(child)
            }
        }

        let windows = value(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        windows.forEach(walk)
        guard url != nil else { return nil }
        return ClaudeChatSnapshot(
            pageTitle: pageTitle, url: url, buttonLabels: buttons, texts: texts)
    }

    private func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var result: AnyObject?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        return status == .success ? result : nil
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
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

    init(model: NotchModel) {
        self.model = model
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        guard !reading, model.settings.showClaudeChats, AXIsProcessTrusted() else { return }
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
