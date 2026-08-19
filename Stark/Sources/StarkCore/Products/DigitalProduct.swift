//
//  StarkCore
//
import Foundation

/// A thing the server promotes, plus the honesty constraints around it.
public struct DigitalProduct: Codable, Sendable, Identifiable, Equatable {
  public var id: String
  public var name: String
  /// One sentence describing what it does for whom.
  public var pitch: String
  /// Concrete capabilities the model may claim. Anything not listed here is
  /// something the model has been told it must not assert.
  public var facts: [String]
  /// Known limitations. Supplying these is what keeps replies credible.
  public var limitations: [String]
  public var url: String
  public var price: String?
  /// Words in an inbound message that make this product relevant.
  public var keywords: [String]
  /// Words that mean "do not pitch here" — support complaints, refund threads,
  /// anything where a promotion would be tone-deaf.
  public var negativeKeywords: [String]

  public init(
    id: String = UUID().uuidString,
    name: String,
    pitch: String,
    facts: [String] = [],
    limitations: [String] = [],
    url: String,
    price: String? = nil,
    keywords: [String] = [],
    negativeKeywords: [String] = ["refund", "scam", "lawsuit", "chargeback", "grief", "died", "funeral"]
  ) {
    self.id = id
    self.name = name
    self.pitch = pitch
    self.facts = facts
    self.limitations = limitations
    self.url = url
    self.price = price
    self.keywords = keywords
    self.negativeKeywords = negativeKeywords
  }

  /// Cheap lexical relevance score in 0...1 for an inbound message.
  ///
  /// Runs before the model does, so obviously irrelevant traffic never costs a
  /// generation pass.
  public func relevance(to text: String) -> Double {
    let haystack = text.lowercased()
    guard !keywords.isEmpty else { return 0.5 }
    if negativeKeywords.contains(where: { haystack.contains($0.lowercased()) }) { return 0 }
    let hits = keywords.filter { haystack.contains($0.lowercased()) }.count
    return min(1.0, Double(hits) / Double(min(3, keywords.count)))
  }

  /// The block handed to the model. Limitations are included deliberately.
  public func brief() -> String {
    var lines = ["Product: \(name) — \(pitch)", "Link: \(url)"]
    if let price { lines.append("Price: \(price)") }
    if !facts.isEmpty {
      lines.append("True things you may state: " + facts.map { "• \($0)" }.joined(separator: " "))
    }
    if !limitations.isEmpty {
      lines.append("Limitations you must not hide: " + limitations.map { "• \($0)" }.joined(separator: " "))
    }
    lines.append("Claim nothing beyond the list above. If asked something you do not know, say you do not know.")
    return lines.joined(separator: "\n")
  }
}
