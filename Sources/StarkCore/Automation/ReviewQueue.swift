//
//  StarkCore
//
import Foundation

/// Holds drafts between generation and sending.
///
/// This is the component that makes the difference between an assistant and a
/// spam cannon: in the default publishing mode nothing leaves the phone until
/// somebody taps approve here.
public actor ReviewQueue {
  private let store = JSONStore<[Draft]>(filename: "queue.json") { [] }
  private var drafts: [Draft] = []
  private var loaded = false
  private let capacity = 300

  public init() {}

  private func hydrate() async {
    guard !loaded else { return }
    loaded = true
    drafts = await store.load()
  }

  private func persist() async {
    if drafts.count > capacity { drafts.removeFirst(drafts.count - capacity) }
    await store.save(drafts)
  }

  public func add(_ draft: Draft) async {
    await hydrate()
    drafts.append(draft)
    await persist()
  }

  public func all() async -> [Draft] {
    await hydrate()
    return drafts.sorted { $0.createdAt > $1.createdAt }
  }

  public func pending() async -> [Draft] {
    await all().filter { $0.status == .pending }
  }

  public func draft(_ id: String) async -> Draft? {
    await hydrate()
    return drafts.first { $0.id == id }
  }

  /// True when this inbound item already produced a draft, so a re-poll that
  /// returns the same mention does not double-reply.
  public func hasDraft(forItem itemID: String) async -> Bool {
    await hydrate()
    return drafts.contains { $0.item.id == itemID }
  }

  /// The last `limit` texts that were actually sent, for the similarity check.
  public func recentSentTexts(limit: Int) async -> [String] {
    await all().filter { $0.status == .sent }.prefix(limit).map(\.finalText)
  }

  @discardableResult
  public func update(_ id: String, _ body: @Sendable (inout Draft) -> Void) async -> Draft? {
    await hydrate()
    guard let index = drafts.firstIndex(where: { $0.id == id }) else { return nil }
    body(&drafts[index])
    let updated = drafts[index]
    await persist()
    return updated
  }

  @discardableResult
  public func setStatus(_ id: String, _ status: Draft.Status, failure: String? = nil) async -> Draft? {
    await update(id) { draft in
      draft.status = status
      draft.decidedAt = Date()
      if let failure { draft.failure = failure }
    }
  }

  public func removeDecided(olderThan age: TimeInterval) async {
    await hydrate()
    let cutoff = Date().addingTimeInterval(-age)
    drafts.removeAll { $0.status != .pending && ($0.decidedAt ?? $0.createdAt) < cutoff }
    await persist()
  }
}
