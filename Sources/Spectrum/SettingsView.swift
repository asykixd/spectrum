import ServiceManagement
import SpectrumCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: NotchModel

    var body: some View {
        Form {
            Section("General") {
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { model.launchAtLogin.isRequested }, set: model.setLaunchAtLogin)
                )
                .disabled(model.launchAtLogin == .unavailable)
                if model.launchAtLogin == .unavailable {
                    Text("Open Spectrum.app to manage launch at login.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if model.launchAtLogin == .needsApproval {
                    Text("Allow Spectrum in Login Items to finish enabling launch at login.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Login Items", action: SMAppService.openSystemSettingsLoginItems)
                }
                if let error = model.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Notch") {
                Toggle("Show music while it plays", isOn: $model.settings.showMusic)
                Toggle(isOn: $model.settings.showLyrics) {
                    Text("Show synced lyrics in the expanded player")
                    Text("Looks up the playing track's title and artist on lrclib.net.")
                }
                Toggle(
                    "Trackpad haptics when the island opens and closes",
                    isOn: $model.settings.haptics)
                Toggle(
                    "Blink when an agent needs permission or an answer",
                    isOn: $model.settings.alertWhenNeeded)
                Toggle(
                    "Flash a checkmark when a task finishes", isOn: $model.settings.flashWhenDone)
                Picker("Agents panel shortcut", selection: $model.settings.shortcut) {
                    Text("Double-tap ⌘").tag(SpectrumSettings.Shortcut.doubleCommand)
                    Text("Double-tap ⌥").tag(SpectrumSettings.Shortcut.doubleOption)
                    Text("Double-tap ⌃").tag(SpectrumSettings.Shortcut.doubleControl)
                }
            }
            Section("Agents") {
                Picker("Office characters", selection: $model.settings.characters) {
                    Text("Clawd").tag(SpectrumSettings.CharacterStyle.clawd)
                    Text("People").tag(SpectrumSettings.CharacterStyle.people)
                }
                Toggle(
                    "Reply to idle Claude Code sessions from the panel",
                    isOn: $model.settings.replyFromPanel)
                Toggle(isOn: $model.settings.answerPermissions) {
                    Text("Allow or deny permission requests from the island")
                    Text(
                        "Hover the warning to answer. Without an answer the terminal asks after a minute."
                    )
                }
                Toggle(isOn: $model.settings.showClaudeChats) {
                    Text("Show chats from the Claude app")
                    Text(
                        "Uses extra battery: Spectrum reads the Claude app's window, and the app keeps more work going while it's read."
                    )
                }
                Toggle("Pause chat tracking on battery", isOn: $model.settings.pauseChatsOnBattery)
                    .disabled(!model.settings.showClaudeChats)
                Picker("Keep chats listed for", selection: $model.settings.chatRetentionMinutes) {
                    ForEach([5, 15, 30, 60], id: \.self) { Text("\($0) minutes").tag($0) }
                }
                .disabled(!model.settings.showClaudeChats)
                Picker(
                    "Drop silent coding sessions after",
                    selection: $model.settings.staleAgentMinutes
                ) {
                    ForEach([15, 30, 60, 180], id: \.self) { minutes in
                        Text(minutes < 60 ? "\(minutes) minutes" : "\(minutes / 60) h").tag(minutes)
                    }
                }
            }
            Section("Agent Hooks") {
                ForEach(AgentProvider.allCases, id: \.self) { provider in
                    LabeledContent(provider.name) {
                        HStack {
                            let installed = model.installedHooks.contains(provider)
                            Text(installed ? "Installed" : "Not installed")
                                .foregroundStyle(.secondary)
                            if installed {
                                Button("Remove") { model.onRemoveHooks(provider) }
                            } else {
                                Button("Install") { model.onInstallHooks(provider) }
                            }
                        }
                    }
                }
                if model.installedHooks.contains(.codex) {
                    Text("Trust Spectrum’s hooks in Codex Settings → Hooks or /hooks in the CLI.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                HStack {
                    Spacer()
                    Button("Quit Spectrum") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            model.refreshLaunchAtLogin()
        }
    }
}
