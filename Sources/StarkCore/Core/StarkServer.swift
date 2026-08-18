//
//  StarkCore
//
import Foundation

/// The whole thing in one object: HTTP control surface, automation engine and
/// persistent state.
///
/// An app creates one of these, hands it a model runtime, and calls `start()`.
@MainActor
public final class StarkServer {
  public let engine: AutomationEngine
  public private(set) var http: HTTPServer?
  public private(set) var url: URL?
  public private(set) var token: String = ""

  public init(model: (any LanguageModel)? = nil) {
    self.engine = AutomationEngine(model: model)
  }

  /// Boots the listener and, if the config asks for it, the automation loop.
  /// Returns the URL to open in Safari.
  @discardableResult
  public func start(startEngine: Bool = true) async throws -> URL {
    let config = await engine.config()
    token = config.apiToken
    await engine.metrics.hydrate()

    let routes = APIRoutes(engine: engine).router()
    let server = HTTPServer(port: config.port, loopbackOnly: config.loopbackOnly) { request in
      await routes.handle(request)
    }
    try await server.start()
    http = server

    let host = config.loopbackOnly ? "127.0.0.1" : "0.0.0.0"
    let url = URL(string: "http://\(host):\(config.port)/")!
    self.url = url
    await EventLog.shared.info("stark", "console at \(url.absoluteString) — token \(config.apiToken.prefix(6))…")

    if let modelID = config.activeModelID, let model = await engine.attachedModel() {
      Task {
        try? await model.load(modelID: modelID) { progress, detail in
          Task { await EventLog.shared.debug("model", "\(Int(progress * 100))% \(detail)") }
        }
      }
    }
    if startEngine { await engine.start() }
    return url
  }

  public func stop() async {
    await engine.stop()
    await http?.stop()
    http = nil
  }

  /// Entry point for a `BGProcessingTask` handler: run one pass and return,
  /// which is all the system will let the app do in the background.
  @discardableResult
  public func runBackgroundPass() async -> Int {
    await engine.runOnce()
  }

  public func attach(model: any LanguageModel) async {
    await engine.attach(model: model)
  }

  /// Seeds a first product and persona so a fresh install is not an empty box.
  public func seedIfEmpty(product: DigitalProduct) async {
    guard await engine.products().isEmpty else { return }
    await engine.upsert(product: product)
  }
}
