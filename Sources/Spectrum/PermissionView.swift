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
                        if let detail = request.prompt.detail {
                            Text(detail)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color(hex: 0xF59E0B).opacity(0.9))
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 6) {
                        answer("Allow", fill: Color(hex: 0x4ADE80), text: .black) {
                            model.answerPermission(.allow)
                        }
                        answer("Deny", fill: .white.opacity(0.12), text: .white) {
                            model.answerPermission(.deny)
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
                .frame(width: 72, height: 26)
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
