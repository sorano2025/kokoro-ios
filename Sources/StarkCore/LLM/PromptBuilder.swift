//
//  StarkCore
//
import Foundation

/// Assembles the chat messages handed to the model.
///
/// The system prompt carries the persona, the product facts *and* the product's
/// limitations. Giving a small model an explicit "here is what you may not
/// claim" list is far more effective than hoping it stays honest, and it is
/// what keeps a 4B model from inventing features under pressure.
public struct PromptBuilder: Sendable {
  public let persona: Persona
  public let publishing: PublishingPolicy

  public init(persona: Persona, publishing: PublishingPolicy) {
    self.persona = persona
    self.publishing = publishing
  }

  public func replyMessages(to item: InboundItem, product: DigitalProduct?, threadContext: [InboundItem] = []) -> [ChatMessage] {
    var system = persona.styleBrief()
    if let product {
      system += "\n\n" + product.brief()
    } else {
      system += "\n\nYou have no product to mention here. Just be useful."
    }
    if publishing.discloseAutomation {
      system += "\n\nThis reply is posted by an automated account. Do not claim to be a human, and do not invent personal experiences you did not have."
    }
    system += "\n\nOutput only the reply text. No preamble, no quotes around it, no markdown."

    var user = "Platform: \(item.platform.rawValue)\nFrom: \(item.authorHandle)\n"
    if !threadContext.isEmpty {
      user += "Earlier in the thread:\n"
      for previous in threadContext.suffix(4) {
        user += "  \(previous.authorHandle): \(previous.text.prefix(280))\n"
      }
    }
    user += "\nMessage to answer:\n\(item.text.prefix(2000))\n\nWrite the reply."

    return [ChatMessage(.system, system), ChatMessage(.user, user)]
  }

  /// Asks the model whether a message is worth answering at all.
  ///
  /// A yes/no pass with a tiny token budget is cheaper than generating a reply
  /// that the guardrails then throw away, and it catches the cases keyword
  /// matching gets wrong — sarcasm, a competitor's name, a rhetorical question.
  public func triageMessages(for item: InboundItem, product: DigitalProduct) -> [ChatMessage] {
    let system = """
    You decide whether replying would genuinely help the person, and whether mentioning a product would be appropriate rather than spammy.
    Answer with one word: REPLY or SKIP. Skip anything that is a joke, a rant, a support complaint, or already answered.
    """
    let user = """
    Product: \(product.name) — \(product.pitch)
    Message from \(item.authorHandle): \(item.text.prefix(1200))
    One word:
    """
    return [ChatMessage(.system, system), ChatMessage(.user, user)]
  }
}
