//
//  JarvisClient
//
import SwiftUI

/// A single chat bubble, styled differently for the user vs. Jarvis.
struct MessageBubbleView: View {
  let message: ChatMessage

  private var isUser: Bool { message.role == .user }

  var body: some View {
    HStack {
      if isUser { Spacer(minLength: 40) }

      Text(message.content.isEmpty ? "…" : message.content)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isUser ? Color.accentColor : Color.gray.opacity(0.15))
        .foregroundStyle(isUser ? Color.white : Color.primary)
        .clipShape(RoundedRectangle(cornerRadius: 16))

      if !isUser { Spacer(minLength: 40) }
    }
  }
}
