import SpectrumCore
import SwiftUI

/// A permission request opened by hovering the warning: what the agent wants, allow or deny.
struct PermissionView: View {
    let model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.geometry.notch.height)
            if let request = model.permissionRequest {
                HStack(alignment: .center, spacing: 12) {
                    AgentAvatar(session: request.session, style: model.settings.characters)
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(request.session.projectName)
                                .foregroundStyle(.white)
                            Text("wants to use \(request.prompt.tool)")
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        if let detail = request.prompt.detail {
                            Text(detail)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color(hex: 0xF59E0B).opacity(0.9))
                                .lineLimit(request.prompt.projectRule == nil ? 2 : 4)
                                .truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 6) {
                        answer("Allow Once", fill: Color(hex: 0x4ADE80), text: .black) {
                            model.answerPermission(.allow, for: request.session)
                        }
                        if let rule = request.prompt.projectRule {
                            answer("Always Allow", fill: .white.opacity(0.12), text: .white) {
                                model.answerPermission(.alwaysAllow(rule), for: request.session)
                            }
                            .help("Allow this exact command in this project")
                        }
                        answer("Deny", fill: .white.opacity(0.12), text: .white) {
                            model.answerPermission(.deny, for: request.session)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func answer(
        _ title: String, fill: Color, text: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
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
