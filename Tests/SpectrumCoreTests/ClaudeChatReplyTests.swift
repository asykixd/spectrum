import Foundation
import Testing

@testable import SpectrumCore

@Test func claudeChatReplyVerifiesTheOpenConversationAndSendButton() {
    let open = URL(string: "https://claude.ai/chat/abc")
    #expect(ClaudeChatReply.matches(sessionID: "claude-chat-abc", url: open))
    #expect(!ClaudeChatReply.matches(sessionID: "claude-chat-other", url: open))
    #expect(
        !ClaudeChatReply.matches(
            sessionID: "claude-chat-abc", url: URL(string: "https://example.org/chat/abc")))
    #expect(
        !ClaudeChatReply.matches(
            sessionID: "claude-chat-abc", url: URL(string: "https://claude.ai/new")))
    #expect(ClaudeChatReply.isSendButton(" Send Message "))
    #expect(ClaudeChatReply.isSendButton("Отправить"))
    #expect(!ClaudeChatReply.isSendButton("Send feedback"))
}
