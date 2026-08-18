//
//  StarkUI
//
#if canImport(SwiftUI)
import Foundation
import Observation
import StarkCore

/// Talks to the engine in-process rather than over the loopback HTTP API.
///
/// The web console exists so the phone can be driven from a laptop; the native
/// screen is on the same side of the socket as the engine, so it skips it.
@MainActor
@Observable
public final class StarkViewModel {
  public var metrics = MetricsSnapshot()
  public var connections: [Connection] = []
  public var products: [DigitalProduct] = []
  public var drafts: [Draft] = []
  public var logs: [LogEntry] = []
  public var model = ModelStatus()
  public var config = StarkConfig()
  public var engineRunning = false
  public var consoleURL: URL?
  public var busy: String?

  private let server: StarkServer
  private var refreshTask: Task<Void, Never>?

  public init(server: StarkServer) {
    self.server = server
    self.consoleURL = server.url
  }

  public func startRefreshing(every seconds: TimeInterval = 3) {
    guard refreshTask == nil else { return }
    refreshTask = Task { [weak self] in
      while !Task.isCancelled {
        await self?.refresh()
        try? await Task.sleep(for: .seconds(seconds))
      }
    }
  }

  public func stopRefreshing() {
    refreshTask?.cancel()
    refreshTask = nil
  }

  public func refresh() async {
    let engine = server.engine
    metrics = await engine.snapshot()
    connections = await engine.connections()
    products = await engine.products()
    drafts = await engine.queue.all()
    model = await engine.modelStatus()
    config = await engine.config()
    engineRunning = await engine.isRunning()
    logs = await EventLog.shared.recent(limit: 120)
    consoleURL = server.url
  }

  public var pendingDrafts: [Draft] { drafts.filter { $0.status == .pending } }

  // MARK: - Actions

  public func runOnce() async {
    busy = "polling"
    defer { busy = nil }
    _ = await server.engine.runOnce()
    await refresh()
  }

  public func toggleEngine() async {
    if engineRunning { await server.engine.stop() } else { await server.engine.start() }
    await refresh()
  }

  public func approve(_ draft: Draft, editedText: String?) async {
    busy = "sending"
    defer { busy = nil }
    _ = await server.engine.approve(draftID: draft.id, editedText: editedText)
    await refresh()
  }

  public func reject(_ draft: Draft) async {
    await server.engine.reject(draftID: draft.id)
    await refresh()
  }

  public func setMode(_ mode: PublishingPolicy.Mode) async {
    _ = await server.engine.updateConfig { $0.publishing.mode = mode }
    await refresh()
  }

  public func addConnection(kind: PlatformKind, label: String, endpoint: String, token: String, options: [String: String] = [:]) async {
    let connection = Connection(kind: kind, label: label, endpoint: endpoint, options: options)
    TokenStore.set(token, for: connection.id)
    await server.engine.upsert(connection: connection)
    _ = await server.engine.verifyConnection(connection.id)
    await refresh()
  }

  public func verify(_ connection: Connection) async {
    busy = "verifying"
    defer { busy = nil }
    _ = await server.engine.verifyConnection(connection.id)
    await refresh()
  }

  public func toggle(_ connection: Connection) async {
    var updated = connection
    updated.enabled.toggle()
    await server.engine.upsert(connection: updated)
    await refresh()
  }

  public func remove(_ connection: Connection) async {
    await server.engine.removeConnection(connection.id)
    await refresh()
  }

  public func addProduct(_ product: DigitalProduct) async {
    await server.engine.upsert(product: product)
    await refresh()
  }

  public func removeProduct(_ product: DigitalProduct) async {
    await server.engine.removeProduct(product.id)
    await refresh()
  }

  public func load(model descriptor: ModelDescriptor) async {
    guard let runtime = await server.engine.attachedModel() else { return }
    busy = "loading \(descriptor.name)"
    _ = await server.engine.updateConfig { $0.activeModelID = descriptor.id }
    Task { [weak self] in
      defer { Task { @MainActor in self?.busy = nil } }
      try? await runtime.load(modelID: descriptor.id) { progress, detail in
        Task { await EventLog.shared.debug("model", "\(Int(progress * 100))% \(detail)") }
      }
      await self?.refresh()
    }
  }

  /// Drafts against pasted text without touching any platform.
  public func preview(text: String) async -> Draft? {
    busy = "drafting"
    defer { busy = nil }
    let item = InboundItem(
      id: "preview-\(UUID().uuidString.prefix(8))",
      connectionID: "preview",
      platform: .generic,
      threadID: "preview",
      authorHandle: "@someone",
      text: text,
      createdAt: Date()
    )
    return await server.engine.makeDraft(for: item, config: config, products: products)
  }
}
#endif
