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

private func hookProvider() -> AgentProvider {
    guard let name = arguments.dropFirst().first else { return .claude }
    guard let provider = AgentProvider(rawValue: name), arguments.count == 2 else {
        fail("expected provider claude or codex")
    }
    return provider
}

switch arguments.first {
case "hook":
    // A hook must be silent and successful even when the app isn't running. Only an explicit
    // permission decision goes to stdout; an empty answer lets the agent show its own prompt.
    let input = FileHandle.standardInput.readDataToEndOfFile()
    let provider = arguments.dropFirst().first.flatMap(AgentProvider.init(rawValue:)) ?? .claude
    let terminalTab = TerminalTab.capture(environment: ProcessInfo.processInfo.environment)
    guard
        let payload = try? AgentEvent.forwardedPayload(
            input, from: provider, terminalTab: terminalTab),
        let event = try? AgentEvent.decode(payload)
    else { exit(0) }
    let path = SpectrumPaths.agentSocket.path
    if event.kind == .permissionRequest {
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
    let provider = hookProvider()
    do {
        try HookInstaller.install(
            executablePath: path, settingsURL: provider.hooksURL, provider: provider)
        print("Installed \(provider.name) hooks in \(provider.hooksURL.path)")
    } catch {
        fail("install failed: \(error)")
    }

case "uninstall-hooks":
    let provider = hookProvider()
    do {
        try HookInstaller.uninstall(settingsURL: provider.hooksURL)
        print("Removed Spectrum hooks from \(provider.hooksURL.path)")
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
