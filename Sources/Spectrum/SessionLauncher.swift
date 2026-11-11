import AppKit
import SpectrumCore

/// Opens and focuses agent sessions in Terminal.
@MainActor
final class SessionLauncher {
    private let model: NotchModel

    init(model: NotchModel) {
        self.model = model
    }

    func start(in directory: String, prompt: String?) {
        let command = NewSession.shellCommand(directory: directory, prompt: prompt)
        var error: NSDictionary?
        NSAppleScript(source: NewSession.appleScript(command: command))?
            .executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "unknown error"
            log.error("opening Terminal failed: \(message)")
            model.newSessionError = "Couldn't open Terminal: \(message)"
            return
        }
        model.newSessionPrompt = ""
        model.newSessionOpen = false
        // Terminal comes to the front; the panel would only sit over it.
        model.agentsOpen = false
    }

    func focus(_ tab: TerminalTab) {
        guard tab.isLive,
            !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal")
                .isEmpty
        else {
            model.terminalError = "This Terminal tab is no longer available."
            return
        }
        var error: NSDictionary?
        let result = NSAppleScript(source: tab.focusScript)?.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            log.error("focusing Terminal failed: \(message)")
            model.terminalError = "Couldn't focus Terminal: \(message)"
        } else if result?.booleanValue == true {
            model.agentsOpen = false
        } else {
            model.terminalError = "This Terminal tab is no longer available."
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"
        panel.message = "Folder to start Claude Code in"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.newSessionDirectory = url.path
    }
}
