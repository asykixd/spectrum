import SpectrumCore
import SwiftUI

struct ClaudeChatReplyView: View {
    @Bindable var model: NotchModel
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    model.selectedSessionID = nil
                } label: {
                    Image(systemName: "chevron.left").frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to Sessions")
                Text(session.projectName)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Open Claude") { model.onOpenChat(session) }
            }
            Text("Claude must have this chat open to receive the reply.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Reply in Claude", text: $model.chatReplyDraft, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.plain)
                    .padding(9)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .disabled(model.chatReplySending)
                Button(model.chatReplySending ? "Sending…" : "Send", action: send)
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        model.chatReplySending
                            || AgentReply.normalizedPrompt(model.chatReplyDraft) == nil)
            }
            if let error = model.chatReplyError {
                Text(error).font(.system(size: 11)).foregroundStyle(Color(hex: 0xF5B544))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }

    private func send() {
        guard let text = AgentReply.normalizedPrompt(model.chatReplyDraft) else { return }
        model.onChatReply(text, session.id)
    }
}
