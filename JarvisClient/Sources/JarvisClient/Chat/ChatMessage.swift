//
//  JarvisClient
//
import Foundation

/// A single message in the conversation with Jarvis.
struct ChatMessage: Identifiable, Equatable {
  enum Role: String {
    case system
    case user
    case assistant
  }

  let id: UUID
  let role: Role
  var content: String

  init(id: UUID = UUID(), role: Role, content: String) {
    self.id = id
    self.role = role
    self.content = content
  }
}
