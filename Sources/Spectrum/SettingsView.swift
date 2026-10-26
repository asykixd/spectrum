import SpectrumCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: NotchModel

    var body: some View {
        Form {
            Section("Notch") {
                Toggle("Show music while it plays", isOn: $model.settings.showMusic)
                Toggle(
                    "Trackpad haptics when the island opens and closes",
                    isOn: $model.settings.haptics)
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
                    "Drop silent Claude Code sessions after",
                    selection: $model.settings.staleAgentMinutes
                ) {
                    ForEach([15, 30, 60, 180], id: \.self) { minutes in
                        Text(minutes < 60 ? "\(minutes) minutes" : "\(minutes / 60) h").tag(minutes)
                    }
                }
            }
            Section("Claude Code") {
                LabeledContent("Hooks") {
                    HStack {
                        Text(model.hooksInstalled ? "Installed" : "Not installed")
                            .foregroundStyle(.secondary)
                        if model.hooksInstalled {
                            Button("Remove", action: model.onRemoveHooks)
                        } else {
                            Button("Install", action: model.onInstallHooks)
                        }
                    }
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
    }
}
