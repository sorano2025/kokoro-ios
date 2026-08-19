//
//  StarkCore
//
import Foundation

/// Wires the HTTP surface onto the automation engine.
///
/// Every `/api` route needs the bearer token from the config. The token is
/// generated on first launch and shown in the app; without it a page on
/// another tab could drive the server through the loopback interface.
public struct APIRoutes: Sendable {
  let engine: AutomationEngine

  public init(engine: AutomationEngine) {
    self.engine = engine
  }

  public func router() -> Router {
    var router = Router()
    let engine = engine

    // MARK: Console
    router.add("GET", "/") { _, _ in .html(Console.page) }
    router.add("GET", "/api/health") { _, _ in
      struct Health: Encodable, Sendable { let ok = true; let service = "stark"; let version = "1.0" }
      return .json(Health())
    }

    // MARK: Stats
    router.add("GET", "/api/stats") { request, _ in
      guard await authorize(request, engine) else { return .error(401, "bad token") }
      struct Payload: Encodable, Sendable {
        let metrics: MetricsSnapshot
        let model: ModelStatus
        let connections: [Connection]
        let engineRunning: Bool
        let lastRun: Date?
        let device: Device
        let mode: String
      }
      struct Device: Encodable, Sendable {
        let memoryBudgetGB: Double
        let physicalMemoryGB: Double
        let freeDiskGB: Double
      }
      return .json(Payload(
        metrics: await engine.snapshot(),
        model: await engine.modelStatus(),
        connections: await engine.connections(),
        engineRunning: await engine.isRunning(),
        lastRun: await engine.lastRun(),
        device: Device(
          memoryBudgetGB: DeviceCapability.memoryBudgetGB,
          physicalMemoryGB: DeviceCapability.physicalMemoryGB,
          freeDiskGB: DeviceCapability.freeDiskGB
        ),
        mode: await engine.config().publishing.mode.rawValue
      ))
    }

    router.add("GET", "/api/logs") { request, _ in
      guard await authorize(request, engine) else { return .error(401, "bad token") }
      return .json(await EventLog.shared.recent(limit: Int(request.query["limit"] ?? "") ?? 150))
    }

    // Live tail: log lines pushed as they happen, so the dashboard does not
    // poll a phone that is trying to save battery.
    router.add("GET", "/api/events") { request, _ in
      guard await authorize(request, engine) else { return .error(401, "bad token") }
      let source = await EventLog.shared.stream()
      let stream = AsyncStream<String> { continuation in
        let task = Task {
          continuation.yield("retry: 3000\n\n")
          for await entry in source {
            let payload = (try? JSONEncoder.stark.encode(entry)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            continuation.yield("event: log\ndata: \(payload)\n\n")
          }
          continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
      }
      return .events(stream)
    }

    // MARK: Config
    router.add("GET", "/api/config") { request, _ in
      guard await authorize(request, engine) else { return .error(401, "bad token") }
      var config = await engine.config()
      config.apiToken = "••••"
      return .json(config)
    }

    router.add("PATCH", "/api/config") { request, _ in
      guard await authorize(request, engine) else { return .error(401, "bad token") }
      struct Patch: Decodable, Sendable {
        var mode: String?
        var tickInterval: TimeInterval?
        var persona: Persona?
        var limits: RateLimits?
        var sampling: SamplingOptions?
        var discloseAutomation: Bool?
      }
      guard let patch = try? request.decode(Patch.self) else { return .error(400, "bad body") }
      let updated = await engine.updateConfig { config in
        if let mode = patch.mode.flatMap(PublishingPolicy.Mode.init(rawValue:)) { config.publishing.mode = mode }
        if let tick = patch.tickInterval { config.tickInterval = max(30, tick) }
        if let persona = patch.persona { config.persona = persona }
        if let limits = patch.limits { config.limits = limits }
        if let sampling = patch.sampling { config.sampling = sampling }
        if let disclose = patch.discloseAutomation { config.publishing.discloseAutomation = disclose }
      }
      var redacted = updated
      redacted.apiToken = "••••"
      return .json(redacted)
    }

    // MARK: Models
    router.add("GET", "/api/models") { request, _ in
      guard await authorize(request, engine) else { return .error(401, "bad token") }
      struct Payload: Encodable, Sendable {
        let catalog: [ModelDescriptor]
        let fits: [String]
        let status: ModelStatus
      }
      return .json(Payload(
        catalog: ModelCatalog.all,
        fits: ModelCatalog.fitting().map(\.id),
        status: await engine.modelStatus()
      ))
    }

    router.add("POST", "/api/models/load") { request, _ in
      guard await authorize(request, engine) else { return .error(401, "bad token") }
      struct Body: Decodable, Sendable { let id: String }
      guard let body = try? request.decode(Body.self) else { return .error(400, "expected {\"id\":…}") }
      guard let model = await engine.attachedModel() else { return .error(503, "no model runtime attached") }
      if let descriptor = ModelCatalog.descriptor(for: body.id) {
        do { try DeviceCapability.check(descriptor) }
        catch { return .error(422, error.localizedDescription) }
      }
      _ = await engine.updateConfig { $0.activeModelID = body.id }
      // Downloads run for minutes; answer immediately and let the dashboard
      // poll `status.progress`.
      Task {
        do {
          try await model.load(modelID: body.id) { progress, detail in
            Task { await EventLog.shared.debug("model", "\(Int(progress * 100))% \(detail)") }
          }
          await EventLog.shared.info("model", "loaded \(body.id)")
        } catch {
          await EventLog.shared.error("model", "load failed: \(error.localizedDescription)")
        }
      }
      return .json(await engine.modelStatus(), status: 202)
    }

    router.add("POST", "/api/models/unload") { request, _ in
      guard await authorize(request, engine) else { return .error(401, "bad token") }
      if let model = await engine.attachedModel() { await model.unload() }
      return .json(await engine.modelStatus())
    }

    // MARK: Connections
    router.add("GET", "/api/connections") { request, _ in
      guard await authorize(request, engine) else { return .error(401, "bad token") }
      return .json(await engine.connections())
    }

    router.add("POST", "/api/connections") { request, _ in
      guard await authorize(request, engine) else { return .error(401, "bad token") }
      struct Body: Decodable, Sendable {
        let id: String?
        let kind: PlatformKind
        let label: String
        let endpoint: String
        let token: String?
        let options: [String: String]?
        let enabled: Bool?
      }
      guard let body = try? request.decode(Body.self) else { return .error(400, "bad body") }
      var connection = Connection(
        id: body.id ?? UUID().uuidString.lowercased(),
        kind: body.kind,
        label: body.label,
        endpoint: body.endpoint,
        options: body.options ?? [:],
        enabled: body.enabled ?? true
      )
      if let token = body.token, !token.isEmpty {
        TokenStore.set(token, for: connection.id)
      }
      if let connector = try? ConnectorFactory.make(connection) {
        connection.health = (try? await connector.verify()) ?? ConnectionHealth(state: .degraded, detail: "not verified")
      }
      await engine.upsert(connection: connection)
      return .json(connection, status: 201)
    }

    router.add("DELETE", "/api/connections/:id") { request, parameters in
      guard await authorize(request, engine) else { return .error(401, "bad token") }
      guard let id = parameters["id"] else { return .error(400, "missing id") }
      await engine.removeConnection(id)
      return HTTPResponse(status: 204)
    }

    router.add("POST", "/api/connections/:id/verify") { request, parameters in
      guard await authorize(request, engine) else { return .error(401, "bad token") }
      guard let id = parameters["id"] else { return .error(400, "missing id") }
      return .json(await engine.verifyConnection(id))
    }

    router.add("POST", "/api/connections/:id/toggle") { request, parameters in
      guard await authorize(request, engine) else { return .error(401, "bad token") }
      guard let id = parameters["id"], var connection = await engine.connections().first(where: { $0.id == id }) else {
        return .error(404, "unknown connection")
      }
      connection.enabled.toggle()
      await engine.upsert(connection: connection)
      return .json(connection)
    }

    // MARK: Products
    router.add("GET", "/api/products") { request, _ in
      guard await authorize(request, engine) else { return .error(401, "bad token") }
      return .json(await engine.products())
    }

    router.add("POST", "/api/products") { request, _ in
      guard await authorize(request, engine) else { return .error(401, "bad token") }
      guard let product = try? request.decode(DigitalProduct.self) else { return .error(400, "bad body") }
      await engine.upsert(product: product)
      return .json(product, status: 201)
    }

    router.add("DELETE", "/api/products/:id") { request, parameters in
      guard await authorize(request, engine) else { return .error(401, "bad token") }
      guard let id = parameters["id"] else { return .error(400, "missing id") }
      await engine.removeProduct(id)
      return HTTPResponse(status: 204)
    }

    // MARK: Queue
    router.add("GET", "/api/queue") { request, _ in
      guard await authorize(request, engine) else { return .error(401, "bad token") }
      let drafts = await engine.queue.all()
      let filtered = request.query["status"].flatMap(Draft.Status.init(rawValue:)).map { status in
        drafts.filter { $0.status == status }
      } ?? drafts
      return .json(Array(filtered.prefix(100)))
    }

    router.add("POST", "/api/queue/:id/approve") { request, parameters in
      guard await authorize(request, engine) else { return .error(401, "bad token") }
      guard let id = parameters["id"] else { return .error(400, "missing id") }
      struct Body: Decodable, Sendable { let text: String? }
      let edited = (try? request.decode(Body.self))?.text
      switch await engine.approve(draftID: id, editedText: edited) {
      case .success(let receipt): return .json(receipt)
      case .failure(let error): return .error(422, error.localizedDescription)
      }
    }

    router.add("POST", "/api/queue/:id/reject") { request, parameters in
      guard await authorize(request, engine) else { return .error(401, "bad token") }
      guard let id = parameters["id"] else { return .error(400, "missing id") }
      await engine.reject(draftID: id)
      return HTTPResponse(status: 204)
    }

    // MARK: Engine control
    router.add("POST", "/api/engine/start") { request, _ in
      guard await authorize(request, engine) else { return .error(401, "bad token") }
      await engine.start()
      return .text("started")
    }

    router.add("POST", "/api/engine/stop") { request, _ in
      guard await authorize(request, engine) else { return .error(401, "bad token") }
      await engine.stop()
      return .text("stopped")
    }

    router.add("POST", "/api/run") { request, _ in
      guard await authorize(request, engine) else { return .error(401, "bad token") }
      struct Result: Encodable, Sendable { let drafted: Int }
      return .json(Result(drafted: await engine.runOnce()))
    }

    // Dry-run a draft against arbitrary text without touching a platform.
    router.add("POST", "/api/draft") { request, _ in
      guard await authorize(request, engine) else { return .error(401, "bad token") }
      struct Body: Decodable, Sendable { let text: String; let author: String? }
      guard let body = try? request.decode(Body.self) else { return .error(400, "bad body") }
      let item = InboundItem(
        id: "preview-\(UUID().uuidString.prefix(8))",
        connectionID: "preview",
        platform: .generic,
        threadID: "preview",
        authorHandle: body.author ?? "@someone",
        text: body.text,
        createdAt: Date()
      )
      guard let draft = await engine.makeDraft(for: item, config: await engine.config(), products: await engine.products()) else {
        return .error(422, "filtered out before generation — see logs")
      }
      return .json(draft)
    }

    return router
  }

  /// Bearer token check, constant time so a wrong token cannot be recovered by
  /// timing the response.
  static func authorize(_ request: HTTPRequest, _ engine: AutomationEngine) async -> Bool {
    let expected = await engine.config().apiToken
    let presented = request.header("authorization")?
      .replacingOccurrences(of: "Bearer ", with: "")
      ?? request.query["token"]
      ?? ""
    let lhs = Array(expected.utf8), rhs = Array(presented.utf8)
    guard lhs.count == rhs.count else { return false }
    var difference: UInt8 = 0
    for (left, right) in zip(lhs, rhs) { difference |= left ^ right }
    return difference == 0
  }
}

/// Free function so route closures can call it without capturing `self`.
private func authorize(_ request: HTTPRequest, _ engine: AutomationEngine) async -> Bool {
  await APIRoutes.authorize(request, engine)
}
