import SpectrumCore
import SwiftUI

/// The recent conversation of one Claude Code session, read from its transcript.
struct ConversationView: View {
    @Bindable var model: NotchModel
    let session: AgentSession

    private var messages: [TranscriptMessage] { model.transcript }
    private var replying: Bool { model.replyingSessionIDs.contains(session.id) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    model.selectedSessionID = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                AgentAvatar(session: session)
                    .scaleEffect(0.8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.projectName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    HStack(spacing: 6) {
                        StatusDot(activity: session.activity)
                        Text(session.statusText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                Spacer()
            }

            if messages.isEmpty {
                Text(
                    session.transcriptPath == nil
                        ? "No transcript yet: it appears after the session's next event."
                        : "Loading conversation…"
                )
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(messages) { MessageBubble(message: $0) }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.never)
                    .onAppear { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                    .onChange(of: messages.last?.id) { _, last in
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }

            if model.settings.replyFromPanel {
                replyBar
            }
        }
    }

    private var replyBar: some View {
        let canReply = AgentReply.canReply(to: session) && !replying
        let placeholder =
            replying
            ? "Claude is working on your message…"
            : canReply ? "Reply to \(session.projectName)…" : "Claude is busy; reply when it stops"
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField(placeholder, text: $model.replyDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .lineLimit(1...3)
                    .disabled(!canReply)
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: replying ? "hourglass" : "arrow.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(ClaudeLook.orange))
                }
                .buttonStyle(.plain)
                .disabled(!canReply || AgentReply.normalizedPrompt(model.replyDraft) == nil)
            }
            .padding(.leading, 12)
            .padding(.trailing, 5)
            .padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(0.09)))
            if let error = model.replyError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: 0xF87171))
                    .lineLimit(1)
                    .padding(.leading, 12)
            }
        }
    }

    private func send() {
        guard let prompt = AgentReply.normalizedPrompt(model.replyDraft) else { return }
        model.onReply(prompt, session)
    }
}

private struct MessageBubble: View {
    let message: TranscriptMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 80)
                Text(message.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: 0x3E63DD)))
            }
        case .assistant:
            HStack {
                Text(message.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.white.opacity(0.09)))
                Spacer(minLength: 80)
            }
        case .tool:
            HStack(spacing: 6) {
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 8, weight: .bold))
                Text(message.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Color(hex: 0x4ADE80, opacity: 0.75))
            .padding(.leading, 6)
        }
    }
}
