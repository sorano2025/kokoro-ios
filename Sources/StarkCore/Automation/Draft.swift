//
//  StarkCore
//
import Foundation

/// A generated reply and everything needed to judge it.
public struct Draft: Codable, Sendable, Identifiable, Equatable {
  public enum Status: String, Codable, Sendable, CaseIterable {
    case pending, approved, sent, rejected, blocked, failed
  }

  public let id: String
  public let item: InboundItem
  public let productID: String?
  /// What the model produced, after the humanizer pass.
  public var text: String
  /// Set when a human edits the draft in the queue; this is what gets sent.
  public var editedText: String?
  public var status: Status
  public var verdict: GuardRails.Verdict
  public var createdAt: Date
  public var decidedAt: Date?
  public var receipt: PostReceipt?
  public var modelID: String?
  public var tokensPerSecond: Double?
  public var failure: String?

  public init(
    id: String = UUID().uuidString.lowercased(),
    item: InboundItem,
    productID: String?,
    text: String,
    status: Status = .pending,
    verdict: GuardRails.Verdict,
    modelID: String? = nil,
    tokensPerSecond: Double? = nil
  ) {
    self.id = id
    self.item = item
    self.productID = productID
    self.text = text
    self.status = status
    self.verdict = verdict
    self.createdAt = Date()
    self.modelID = modelID
    self.tokensPerSecond = tokensPerSecond
  }

  /// The text that would actually be posted.
  public var finalText: String { editedText ?? text }
}
