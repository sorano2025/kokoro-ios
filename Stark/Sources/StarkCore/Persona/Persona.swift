//
//  StarkCore
//
import Foundation

/// The voice the model writes in.
///
/// This is a *style* description, not a disguise: the persona shapes tone and
/// length, while `PublishingPolicy.discloseAutomation` keeps the fact that a
/// bot wrote the text visible. Sounding human and pretending to be a specific
/// human are different things, and only the first one is supported here.
public struct Persona: Codable, Sendable, Equatable {
  /// Display name used in prompts, e.g. "Ada from Northwind".
  public var name: String
  /// One or two sentences on who is speaking and what they know.
  public var background: String
  /// Adjectives the model is told to hit, e.g. ["direct", "warm", "specific"].
  public var tone: [String]
  /// Phrases the model must never produce, checked after generation too.
  public var bannedPhrases: [String]
  /// Preferred reply length in words. Short replies read as human; essays do not.
  public var targetWords: ClosedRange<Int> {
    get { minWords...max(minWords, maxWords) }
    set { minWords = newValue.lowerBound; maxWords = newValue.upperBound }
  }
  private var minWords: Int
  private var maxWords: Int
  /// 0 = never, 1 = at most one, 2 = free rein.
  public var emojiBudget: Int
  /// Contractions, sentence fragments and lowercase openers.
  public var casual: Bool
  /// Optional sign-off appended when it fits the length budget.
  public var signature: String?

  public init(
    name: String = "Stark",
    background: String = "You help people who are already discussing a problem your product solves. You have used the product yourself and know its limits.",
    tone: [String] = ["direct", "concrete", "friendly", "unhurried"],
    bannedPhrases: [String] = Persona.defaultBannedPhrases,
    targetWords: ClosedRange<Int> = 25...70,
    emojiBudget: Int = 0,
    casual: Bool = true,
    signature: String? = nil
  ) {
    self.name = name
    self.background = background
    self.tone = tone
    self.bannedPhrases = bannedPhrases
    self.minWords = targetWords.lowerBound
    self.maxWords = targetWords.upperBound
    self.emojiBudget = emojiBudget
    self.casual = casual
    self.signature = signature
  }

  public static let `default` = Persona()

  /// Tells that make a reply read as machine-written or as a sales pitch.
  public static let defaultBannedPhrases: [String] = [
    "as an ai", "as a language model", "i'm just an ai",
    "delve", "in today's fast-paced", "game-changer", "revolutionary",
    "unlock the power", "seamlessly", "look no further",
    "i hope this helps!", "great question!", "absolutely!",
    "check out my", "dm me", "link in bio",
  ]

  /// Rendered into the system prompt.
  public func styleBrief() -> String {
    var lines: [String] = []
    lines.append("You are \(name). \(background)")
    lines.append("Tone: \(tone.joined(separator: ", ")).")
    lines.append("Length: \(targetWords.lowerBound)-\(targetWords.upperBound) words. Never longer.")
    lines.append(casual
      ? "Write the way a knowledgeable person types in a thread: contractions, plain words, no headings, no bullet lists."
      : "Write in clean, complete sentences. No headings, no bullet lists.")
    switch emojiBudget {
    case 0: lines.append("Do not use emoji.")
    case 1: lines.append("At most one emoji, only if it genuinely fits.")
    default: break
    }
    lines.append("Never use these phrases: \(bannedPhrases.prefix(12).joined(separator: ", ")).")
    lines.append("Answer the person's actual question first. Mention the product only if it is the honest answer, at most once, and say plainly that you are involved with it.")
    lines.append("If the product does not fit their problem, say so and do not pitch it.")
    return lines.joined(separator: "\n")
  }
}
