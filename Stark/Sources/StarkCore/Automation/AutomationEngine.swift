//
//  StarkCore
//
import Foundation

/// The loop: poll every enabled connection, draft a reply for anything worth
/// answering, and either queue it or send it.
///
/// One actor owns the whole cycle so a background wake, a manual "run now" from
/// the dashboard and an approve tap can never interleave into a double post.
public actor AutomationEngine {
  public let queue = ReviewQueue()
  public let metrics = MetricsStore()

  private let configStore = JSONStore<StarkConfig>(filename: "config.json") { StarkConfig() }
  private let connectionStore = JSONStore<[Connection]>(filename: "connections.json") { [] }
  private let productStore = JSONStore<[DigitalProduct]>(filename: "products.json") { [] }

  private var model: (any LanguageModel)?
  private var running = false
  private var lastRunAt: Date?
  private var lastSendAt: [String: Date] = [:]
  private var tickTask: Task<Void, Never>?

  public init(model: (any LanguageModel)? = nil) {
    self.model = model
  }

  // MARK: - State access

  public func config() async -> StarkConfig { await configStore.load() }
  public func updateConfig(_ body: @Sendable (inout StarkConfig) -> Void) async -> StarkConfig {
    await configStore.mutate { config in
      body(&config)
      return config
    }
  }

  public func connections() async -> [Connection] { await connectionStore.load() }
  public func products() async -> [DigitalProduct] { await productStore.load() }

  public func upsert(connection: Connection) async {
    await connectionStore.mutate { list in
      if let index = list.firstIndex(where: { $0.id == connection.id }) {
        list[index] = connection
      } else {
        list.append(connection)
      }
    }
  }

  public func removeConnection(_ id: String) async {
    TokenStore.delete(id)
    await connectionStore.mutate { $0.removeAll { $0.id == id } }
  }

  public func upsert(product: DigitalProduct) async {
    await productStore.mutate { list in
      if let index = list.firstIndex(where: { $0.id == product.id }) {
        list[index] = product
      } else {
        list.append(product)
      }
    }
  }

  public func removeProduct(_ id: String) async {
    await productStore.mutate { $0.removeAll { $0.id == id } }
  }

  public func attach(model: any LanguageModel) { self.model = model }
  public func attachedModel() -> (any LanguageModel)? { model }
  public func modelStatus() async -> ModelStatus {
    guard let model else { return ModelStatus() }
    return await model.status
  }

  public func isRunning() -> Bool { tickTask != nil }
  public func lastRun() -> Date? { lastRunAt }

  // MARK: - Scheduling

  /// Starts the repeating loop. Idempotent.
  public func start() async {
    guard tickTask == nil else { return }
    let interval = await config().tickInterval
    await EventLog.shared.info("engine", "automation loop started, tick \(Int(interval))s")
    tickTask = Task { [weak self] in
      while !Task.isCancelled {
        await self?.runOnce()
        let seconds = await self?.config().tickInterval ?? 120
        try? await Task.sleep(for: .seconds(seconds))
      }
    }
  }

  public func stop() async {
    tickTask?.cancel()
    tickTask = nil
    await EventLog.shared.info("engine", "automation loop stopped")
  }

  /// One full pass. Safe to call directly from a `BGProcessingTask` handler.
  @discardableResult
  public func runOnce() async -> Int {
    guard !running else { return 0 }
    running = true
    defer { running = false }
    lastRunAt = Date()

    let config = await config()
    let products = await products()
    var drafted = 0

    for connection in await connections() where connection.enabled {
      do {
        drafted += try await poll(connection, config: config, products: products)
      } catch {
        await EventLog.shared.error("engine", "\(connection.label): \(error.localizedDescription)")
        await metrics.record(MetricEvent(kind: .failed, connectionID: connection.id))
        await markHealth(connection.id, ConnectionHealth(state: .degraded, detail: error.localizedDescription))
      }
    }
    return drafted
  }

  private func poll(_ connection: Connection, config: StarkConfig, products: [DigitalProduct]) async throws -> Int {
    let connector = try ConnectorFactory.make(connection)
    let items = try await connector.fetchInbox(since: connection.lastPolledAt)
    await metrics.record(MetricEvent(kind: .fetched, connectionID: connection.id, value: Double(items.count)))

    var drafted = 0
    for item in items {
      if await queue.hasDraft(forItem: item.id) { continue }
      if let draft = await makeDraft(for: item, config: config, products: products) {
        await queue.add(draft)
        drafted += 1
        await metrics.record(MetricEvent(kind: .drafted, connectionID: connection.id, threadID: item.threadID, value: Double(draft.text.split(separator: " ").count)))
        if draft.verdict.decision == .send {
          await scheduleSend(draft)
        } else {
          await metrics.record(MetricEvent(kind: .queued, connectionID: connection.id, threadID: item.threadID))
        }
      }
    }

    // Watermark last, so a mid-loop failure re-reads the same window instead of
    // silently skipping messages.
    await connectionStore.mutate { list in
      guard let index = list.firstIndex(where: { $0.id == connection.id }) else { return }
      list[index].lastPolledAt = Date()
      if let newest = Self.newestID(items) { list[index].lastSeenItemID = newest }
      list[index].health = ConnectionHealth(state: .ok)
    }
    return drafted
  }

  /// Highest id in a batch.
  ///
  /// Connectors disagree about ordering — Mastodon returns newest first,
  /// Discord oldest first — so taking the last element as the watermark would
  /// silently rewind one of them. All three platforms use ascending numeric
  /// ids, so the maximum is the honest answer.
  static func newestID(_ items: [InboundItem]) -> String? {
    items.map(\.id).max { lhs, rhs in
      if let left = Int(lhs), let right = Int(rhs) { return left < right }
      return lhs.count == rhs.count ? lhs < rhs : lhs.count < rhs.count
    }
  }

  // MARK: - Drafting

  /// Runs one message through filter → triage → generation → guardrails.
  public func makeDraft(for item: InboundItem, config: StarkConfig, products: [DigitalProduct]) async -> Draft? {
    let rails = GuardRails(limits: config.limits, persona: config.persona, publishing: config.publishing)
    let (ok, reason) = rails.shouldConsider(item, products: products)
    guard ok else {
      await EventLog.shared.debug("engine", "skipped \(item.id): \(reason ?? "filtered")")
      await metrics.record(MetricEvent(kind: .blocked, connectionID: item.connectionID, threadID: item.threadID))
      return nil
    }

    guard let model else {
      await EventLog.shared.warn("engine", "no model loaded, cannot draft")
      return nil
    }

    let product = products
      .map { ($0, $0.relevance(to: item.text)) }
      .filter { $0.1 > 0 }
      .max { $0.1 < $1.1 }

    let builder = PromptBuilder(persona: config.persona, publishing: config.publishing)

    if let product, product.1 < 0.6 {
      let triage = try? await model.complete(
        messages: builder.triageMessages(for: item, product: product.0),
        options: SamplingOptions(temperature: 0.1, topP: 0.9, maxTokens: 4, repetitionPenalty: 1.0)
      )
      if let triage, triage.text.uppercased().contains("SKIP") {
        await EventLog.shared.debug("engine", "model triage skipped \(item.id)")
        await metrics.record(MetricEvent(kind: .blocked, connectionID: item.connectionID, threadID: item.threadID))
        return nil
      }
    }

    let result: (text: String, tokensPerSecond: Double, tokens: Int)
    do {
      result = try await model.complete(
        messages: builder.replyMessages(to: item, product: product?.0),
        options: config.sampling
      )
    } catch {
      await EventLog.shared.error("engine", "generation failed: \(error.localizedDescription)")
      await metrics.record(MetricEvent(kind: .failed, connectionID: item.connectionID))
      return nil
    }
    await metrics.recordThroughput(tokensPerSecond: result.tokensPerSecond)

    let humanizer = Humanizer(persona: config.persona, publishing: config.publishing)
    let polished = humanizer.polish(result.text)

    let hourAgo = Date().addingTimeInterval(-3600)
    let dayAgo = Date().addingTimeInterval(-86400)
    let verdict = rails.evaluate(
      draft: polished,
      item: item,
      recentSent: await queue.recentSentTexts(limit: config.limits.similarityWindow),
      sentLastHourOnConnection: await metrics.count(.sent, since: hourAgo, connectionID: item.connectionID),
      sentTodayOnConnection: await metrics.count(.sent, since: dayAgo, connectionID: item.connectionID),
      sentTodayInThread: await metrics.count(.sent, since: dayAgo, threadID: item.threadID)
    )

    var draft = Draft(
      item: item,
      productID: product?.0.id,
      text: polished,
      status: verdict.decision == .block ? .blocked : .pending,
      verdict: verdict,
      modelID: await model.status.modelID,
      tokensPerSecond: result.tokensPerSecond
    )
    if verdict.decision == .block {
      draft.decidedAt = Date()
      await EventLog.shared.info("engine", "blocked draft for \(item.id): \(verdict.reasons.joined(separator: "; "))")
      await metrics.record(MetricEvent(kind: .blocked, connectionID: item.connectionID, threadID: item.threadID))
    }
    return draft
  }

  // MARK: - Sending

  /// Sends after the pacing delay, so approvals and auto-sends both land at a
  /// human rhythm rather than in a burst.
  private func scheduleSend(_ draft: Draft) async {
    let config = await config()
    let humanizer = Humanizer(persona: config.persona, publishing: config.publishing)
    let elapsed = lastSendAt[draft.item.connectionID].map { Date().timeIntervalSince($0) } ?? .greatestFiniteMagnitude
    let delay = max(0, humanizer.sendDelay() - elapsed)
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      _ = await self?.send(draftID: draft.id)
    }
  }

  /// Posts a draft. Used by the auto path and by the approve button.
  @discardableResult
  public func send(draftID: String) async -> Result<PostReceipt, SendFailure> {
    guard let draft = await queue.draft(draftID) else {
      return .failure(SendFailure("no draft \(draftID)"))
    }
    guard draft.status == .pending || draft.status == .approved else {
      return .failure(SendFailure("draft already \(draft.status.rawValue)"))
    }
    let config = await config()
    if config.publishing.mode == .dryRun {
      await queue.setStatus(draftID, .rejected, failure: "dry run — nothing was sent")
      return .failure(SendFailure("dry run — nothing was sent"))
    }
    guard let connection = await connections().first(where: { $0.id == draft.item.connectionID }) else {
      await queue.setStatus(draftID, .failed, failure: "connection removed")
      return .failure(SendFailure("connection was removed"))
    }

    do {
      let connector = try ConnectorFactory.make(connection)
      let started = Date()
      let receipt = try await connector.send(OutboundPost(text: draft.finalText, inReplyTo: draft.item.replyTarget))
      lastSendAt[connection.id] = Date()
      await queue.update(draftID) { draft in
        draft.status = .sent
        draft.decidedAt = Date()
        draft.receipt = receipt
      }
      await metrics.record(MetricEvent(
        kind: .sent,
        connectionID: connection.id,
        threadID: draft.item.threadID,
        value: Date().timeIntervalSince(started) * 1000
      ))
      await EventLog.shared.info("engine", "sent reply on \(connection.label) → \(receipt.remoteID)")
      return .success(receipt)
    } catch {
      await queue.setStatus(draftID, .failed, failure: error.localizedDescription)
      await metrics.record(MetricEvent(kind: .failed, connectionID: connection.id))
      await EventLog.shared.error("engine", "send failed on \(connection.label): \(error.localizedDescription)")
      return .failure(SendFailure(error))
    }
  }

  public func approve(draftID: String, editedText: String? = nil) async -> Result<PostReceipt, SendFailure> {
    await queue.update(draftID) { draft in
      if let editedText, !editedText.isEmpty { draft.editedText = editedText }
      draft.status = .approved
    }
    await metrics.record(MetricEvent(kind: .approved))
    return await send(draftID: draftID)
  }

  public func reject(draftID: String) async {
    await queue.setStatus(draftID, .rejected)
    await metrics.record(MetricEvent(kind: .rejected))
  }

  // MARK: - Health

  public func verifyConnection(_ id: String) async -> ConnectionHealth {
    guard let connection = await connections().first(where: { $0.id == id }) else {
      return ConnectionHealth(state: .offline, detail: "unknown connection")
    }
    do {
      let health = try await ConnectorFactory.make(connection).verify()
      await markHealth(id, health)
      return health
    } catch {
      let health = ConnectionHealth(state: .offline, detail: error.localizedDescription)
      await markHealth(id, health)
      return health
    }
  }

  private func markHealth(_ id: String, _ health: ConnectionHealth) async {
    await connectionStore.mutate { list in
      guard let index = list.firstIndex(where: { $0.id == id }) else { return }
      list[index].health = health
    }
  }

  public func snapshot() async -> MetricsSnapshot {
    await metrics.snapshot(queueDepth: await queue.pending().count)
  }
}
