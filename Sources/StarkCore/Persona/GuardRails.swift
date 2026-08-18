//
//  StarkCore
//
import Foundation

/// The last thing every draft passes through before it can be sent.
///
/// Rate limits and relevance checks are not politeness — they are what keeps
/// the connected accounts from being suspended. Every platform's automation
/// policy bans unsolicited promotion at volume, so the ceilings here are
/// deliberately low and the default verdict is "a human looks at this first".
public struct GuardRails: Sendable {
  public struct Verdict: Codable, Sendable, Equatable {
    public enum Decision: String, Codable, Sendable { case send, review, block }
    public var decision: Decision
    public var reasons: [String]

    public init(_ decision: Decision, _ reasons: [String] = []) {
      self.decision = decision
      self.reasons = reasons
    }
  }

  public let limits: RateLimits
  public let persona: Persona
  public let publishing: PublishingPolicy

  public init(limits: RateLimits, persona: Persona, publishing: PublishingPolicy) {
    self.limits = limits
    self.persona = persona
    self.publishing = publishing
  }

  /// Cheap pre-generation filter. Returning `false` saves a model pass.
  public func shouldConsider(_ item: InboundItem, products: [DigitalProduct]) -> (ok: Bool, reason: String?) {
    let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.count < 12 { return (false, "message too short to answer usefully") }
    if text.count > 8000 { return (false, "message too long to be a real question") }
    let lowered = text.lowercased()
    for sensitive in Self.sensitiveTopics where lowered.contains(sensitive) {
      return (false, "sensitive topic (\(sensitive)) — not a place for promotion")
    }
    if products.allSatisfy({ $0.relevance(to: text) == 0 }) {
      return (false, "no product is relevant to this message")
    }
    return (true, nil)
  }

  /// Post-generation checks.
  public func evaluate(
    draft: String,
    item: InboundItem,
    recentSent: [String],
    sentLastHourOnConnection: Int,
    sentTodayOnConnection: Int,
    sentTodayInThread: Int
  ) -> Verdict {
    var reasons: [String] = []

    if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return Verdict(.block, ["empty draft"])
    }
    let lowered = draft.lowercased()
    for phrase in persona.bannedPhrases where lowered.contains(phrase.lowercased()) {
      return Verdict(.block, ["contains banned phrase '\(phrase)'"])
    }
    let links = Self.linkCount(in: draft)
    if links > limits.maxLinksPerReply {
      return Verdict(.block, ["\(links) links, limit is \(limits.maxLinksPerReply)"])
    }
    if sentTodayInThread >= limits.repliesPerDayPerThread {
      return Verdict(.block, ["already replied in this thread today"])
    }
    if sentLastHourOnConnection >= limits.repliesPerHourPerPlatform {
      return Verdict(.block, ["hourly limit reached for this connection"])
    }
    if sentTodayOnConnection >= limits.repliesPerDayPerPlatform {
      return Verdict(.block, ["daily limit reached for this connection"])
    }
    if let twin = recentSent.first(where: { Humanizer.similarity($0, draft) > limits.maxSimilarityToRecent }) {
      return Verdict(.block, ["too similar to a recent reply: '\(twin.prefix(48))…'"])
    }
    if publishing.discloseAutomation, !lowered.contains(publishing.disclosureText.lowercased()) {
      reasons.append("disclosure line missing")
      return Verdict(.review, reasons)
    }
    if Self.makesUnverifiableClaim(draft) {
      reasons.append("draft states a number or guarantee that is not in the product facts")
      return Verdict(.review, reasons)
    }

    switch publishing.mode {
    case .dryRun: return Verdict(.review, ["dry run"])
    case .review: return Verdict(.review, ["review mode — every draft is checked by a human"])
    case .autoWithinGuardrails: return Verdict(.send, reasons)
    }
  }

  static func linkCount(in text: String) -> Int {
    let pattern = "(https?://|www\\.)[^\\s)]+"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
    return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
  }

  /// Percentages, "guaranteed", "#1" and similar are the claims that get an
  /// account reported. They are held for review rather than dropped, because
  /// sometimes the number is genuinely in the product facts.
  static func makesUnverifiableClaim(_ text: String) -> Bool {
    let lowered = text.lowercased()
    let redFlags = ["guarantee", "guaranteed", "#1", "best in the world", "risk-free", "instantly", "100%", "no.1"]
    if redFlags.contains(where: { lowered.contains($0) }) { return true }
    return text.range(of: "\\b\\d{2,3}%", options: .regularExpression) != nil
  }

  /// Threads where a promotional reply is inappropriate regardless of keyword
  /// relevance.
  static let sensitiveTopics = [
    "suicide", "self-harm", "kill myself", "abuse", "assault",
    "diagnosis", "cancer", "medication", "overdose",
    "immigration raid", "deportation", "arrested", "lawsuit against",
    "died", "passed away", "funeral", "layoff", "laid off",
  ]
}
