import AppKit
import SpectrumCore

/// Absolute path of this executable, used as the hook command.
private func executablePath() -> String? {
    Bundle.main.executableURL?.resolvingSymlinksInPath().path
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("spectrum: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments.dropFirst()

switch arguments.first {
case "hook":
    // Runs inside every Claude Code hook: must stay silent on stdout (UserPromptSubmit output
    // is fed to the model) and must never fail the agent, even when the app isn't running.
    // The one exception is a permission request the user answered on the island: its decision
    // goes to stdout, and with no answer Claude Code shows its own dialog as usual.
    let payload = FileHandle.standardInput.readDataToEndOfFile()
    let path = SpectrumPaths.agentSocket.path
    if (try? AgentEvent.decode(payload))?.kind == .permissionRequest {
        let wait = TimeInterval(HookInstaller.permissionWait)
        if let answer = try? AgentSocket.request(payload, to: path, timeout: wait),
            !answer.isEmpty
        {
            FileHandle.standardOutput.write(answer)
        }
    } else {
        try? AgentSocket.send(payload, to: path)
    }
    exit(0)

case "install-hooks":
    guard let path = executablePath() else { fail("cannot resolve executable path") }
    do {
        try HookInstaller.install(executablePath: path, settingsURL: SpectrumPaths.claudeSettings)
        print("Installed Claude Code hooks in \(SpectrumPaths.claudeSettings.path)")
    } catch {
        fail("install failed: \(error)")
    }

case "uninstall-hooks":
    do {
        try HookInstaller.uninstall(settingsURL: SpectrumPaths.claudeSettings)
        print("Removed Spectrum hooks from \(SpectrumPaths.claudeSettings.path)")
    } catch {
        fail("uninstall failed: \(error)")
    }

case "preview":
    guard let directory = arguments.dropFirst().first else { fail("usage: Spectrum preview <dir>") }
    MainActor.assumeIsolated {
        do {
            try PreviewRenderer.render(to: URL(fileURLWithPath: directory))
        } catch {
            fail("preview failed: \(error)")
        }
    }

case nil:
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

case let other?:
    fail("unknown command \(other); expected hook, install-hooks, uninstall-hooks or preview")
}
