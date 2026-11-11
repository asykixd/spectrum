import SpectrumCore
import SwiftUI

/// The permission request opened by hovering the warning.
struct PermissionView: View {
    let model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.geometry.notch.height)
            if let request = model.permissionRequest {
                PermissionCard(model: model, session: request.session, prompt: request.prompt)
                    .padding(.horizontal, 18)
                    .frame(maxHeight: .infinity)
            }
        }
    }
}

struct PermissionCard: View {
    let model: NotchModel
    let session: AgentSession
    let prompt: PermissionPrompt

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AgentAvatar(session: session, style: model.settings.characters)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(session.projectName)
                        .foregroundStyle(.white)
                    Text("wants to use \(prompt.tool)")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                if let detail = prompt.detail {
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xF59E0B).opacity(0.9))
                        .lineLimit(prompt.projectRule == nil ? 2 : 4)
                        .truncationMode(.middle)
                }
                Text("Return allows once · Esc denies")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 6) {
                answer("Allow Once", fill: Color(hex: 0x4ADE80), text: .black, decision: .allow)
                if let rule = prompt.projectRule {
                    answer(
                        "Always Allow", fill: .white.opacity(0.12), text: .white,
                        decision: .alwaysAllow(rule)
                    )
                    .help("Allow this exact command in this project")
                }
                answer("Deny", fill: .white.opacity(0.12), text: .white, decision: .deny)
            }
        }
    }

    private func answer(
        _ title: String, fill: Color, text: Color, decision: PermissionDecision
    ) -> some View {
        Button {
            model.answerPermission(decision, for: session)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(text)
                .frame(width: 94, height: 26)
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
