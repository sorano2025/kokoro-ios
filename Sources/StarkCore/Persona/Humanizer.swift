//
//  StarkCore
//
import Foundation

/// Turns raw model output into something that reads like a person typed it.
///
/// The work is subtraction, not disguise: chat models open with "Certainly!",
/// wrap answers in markdown, restate the question and run long. Stripping that
/// is what makes a reply sound human. Fake typos and invented biographical
/// detail are deliberately not in here — that is impersonation, and the
/// disclosure line added at the end exists to prevent exactly that reading.
public struct Humanizer: Sendable {
  public let persona: Persona
  public let publishing: PublishingPolicy

  public init(persona: Persona, publishing: PublishingPolicy) {
    self.persona = persona
    self.publishing = publishing
  }

  public func polish(_ raw: String) -> String {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    text = stripThinking(text)
    text = stripWrappingQuotes(text)
    text = stripMarkdown(text)
    text = stripOpeners(text)
    text = enforceEmojiBudget(text)
    text = collapseWhitespace(text)
    text = trimToWordBudget(text)
    text = appendSignature(text)
    text = appendDisclosure(text)
    return text
  }

  /// Reasoning models emit a `<think>` block before the answer.
  private func stripThinking(_ text: String) -> String {
    guard let end = text.range(of: "</think>") else { return text }
    return String(text[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func stripWrappingQuotes(_ text: String) -> String {
    var text = text
    if text.hasPrefix("```") {
      text = text.replacingOccurrences(of: "^```[a-zA-Z]*\\n", with: "", options: .regularExpression)
      if text.hasSuffix("```") { text.removeLast(3) }
    }
    let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("'", "'")]
    for (open, close) in pairs where text.first == open && text.last == close && text.count > 2 {
      text = String(text.dropFirst().dropLast())
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func stripMarkdown(_ text: String) -> String {
    var text = text
    text = text.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: [.regularExpression])
    text = text.replacingOccurrences(of: "(?m)^\\s*[-*•]\\s+", with: "", options: [.regularExpression])
    text = text.replacingOccurrences(of: "(?m)^\\s*\\d+\\.\\s+", with: "", options: [.regularExpression])
    text = text.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: [.regularExpression])
    text = text.replacingOccurrences(of: "(?<!\\w)_(.+?)_(?!\\w)", with: "$1", options: [.regularExpression])
    return text
  }

  /// Chat-assistant throat-clearing at the start of a reply.
  private func stripOpeners(_ text: String) -> String {
    let openers = [
      "certainly", "sure", "of course", "absolutely", "great question",
      "happy to help", "i'd be happy to help", "thanks for reaching out",
      "that's a great point", "i understand", "here's",
    ]
    var text = text
    var changed = true
    while changed {
      changed = false
      let lowered = text.lowercased()
      for opener in openers where lowered.hasPrefix(opener) {
        let remainder = text.dropFirst(opener.count)
        guard let separator = remainder.firstIndex(where: { $0 == "," || $0 == "!" || $0 == "." || $0 == ":" }),
              remainder.distance(from: remainder.startIndex, to: separator) < 3
        else { continue }
        text = String(remainder[remainder.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        changed = true
        break
      }
    }
    return text
  }

  private func enforceEmojiBudget(_ text: String) -> String {
    guard persona.emojiBudget < 2 else { return text }
    var seen = 0
    var output = String.UnicodeScalarView()
    for scalar in text.unicodeScalars {
      if scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && scalar.value > 0x238C) {
        seen += 1
        if seen > persona.emojiBudget { continue }
      }
      output.append(scalar)
    }
    return String(output)
  }

  private func collapseWhitespace(_ text: String) -> String {
    text
      .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Cuts at a sentence boundary rather than mid-thought when the model
  /// overshoots the persona's word budget.
  private func trimToWordBudget(_ text: String) -> String {
    let words = text.split(separator: " ")
    guard words.count > persona.targetWords.upperBound else { return text }
    let clipped = words.prefix(persona.targetWords.upperBound).joined(separator: " ")
    if let lastStop = clipped.lastIndex(where: { ".!?".contains($0) }) {
      let sentence = String(clipped[...lastStop])
      if sentence.split(separator: " ").count >= persona.targetWords.lowerBound { return sentence }
    }
    return clipped + "…"
  }

  private func appendSignature(_ text: String) -> String {
    guard let signature = persona.signature, !signature.isEmpty, !text.contains(signature) else { return text }
    return text + "\n— " + signature
  }

  private func appendDisclosure(_ text: String) -> String {
    guard publishing.discloseAutomation else { return text }
    let disclosure = publishing.disclosureText
    guard !disclosure.isEmpty, !text.lowercased().contains(disclosure.lowercased()) else { return text }
    return text + " " + disclosure
  }

  /// Similarity of two drafts as Jaccard overlap over word trigrams.
  /// Catches the "same canned answer, different nouns" failure that makes an
  /// automated account obvious.
  public static func similarity(_ lhs: String, _ rhs: String) -> Double {
    let left = trigrams(lhs), right = trigrams(rhs)
    guard !left.isEmpty, !right.isEmpty else { return 0 }
    let intersection = left.intersection(right).count
    let union = left.union(right).count
    return union == 0 ? 0 : Double(intersection) / Double(union)
  }

  private static func trigrams(_ text: String) -> Set<String> {
    let words = text.lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
    guard words.count >= 3 else { return Set(words) }
    return Set((0...(words.count - 3)).map { words[$0...($0 + 2)].joined(separator: " ") })
  }

  /// How long to wait before this send, so replies land at a human cadence
  /// instead of all at once the moment a poll returns.
  public func sendDelay() -> TimeInterval {
    publishing.minSecondsBetweenSends + TimeInterval.random(in: publishing.sendJitter)
  }
}
