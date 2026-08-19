//
//  StarkCore
//
import Foundation
import Network

/// A small HTTP/1.1 server built on Network.framework.
///
/// Network.framework rather than a third-party server package: it is the only
/// socket stack iOS keeps alive across the app-state transitions this thing
/// lives through, it needs no dependency, and NWListener gives the local-only
/// binding that keeps the control surface off the wider network.
public actor HTTPServer {
  public typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

  public private(set) var port: UInt16
  public private(set) var isListening = false
  private let loopbackOnly: Bool
  private let handler: Handler
  private var listener: NWListener?
  private let queue = DispatchQueue(label: "stark.http", qos: .userInitiated)

  /// Network.framework's connection object is thread-safe but not marked
  /// `Sendable`, and it has to travel from the listener's callback into this
  /// actor. The box states the guarantee the framework already makes.
  private final class Handle: @unchecked Sendable {
    let connection: NWConnection
    init(_ connection: NWConnection) { self.connection = connection }
  }

  public init(port: UInt16, loopbackOnly: Bool, handler: @escaping Handler) {
    self.port = port
    self.loopbackOnly = loopbackOnly
    self.handler = handler
  }

  public func start() throws {
    guard listener == nil else { return }
    let parameters = NWParameters.tcp
    parameters.allowLocalEndpointReuse = true
    if loopbackOnly {
      // Binding the loopback address is the difference between "reachable from
      // Safari on this phone" and "reachable from every device on the café
      // Wi-Fi".
      parameters.requiredInterfaceType = .loopback
    }
    guard let nwPort = NWEndpoint.Port(rawValue: port) else {
      throw ConnectorError.notConfigured("port \(port)")
    }
    let listener = try NWListener(using: parameters, on: nwPort)
    listener.newConnectionHandler = { [weak self] connection in
      guard let self else { return }
      let handle = Handle(connection)
      Task { await self.accept(handle) }
    }
    listener.stateUpdateHandler = { [weak self] state in
      // Only Sendable values cross into the actor: the state enum carries an
      // NWError, so the message is extracted here.
      switch state {
      case .ready:
        Task { await self?.markReady() }
      case .failed(let error):
        let message = error.localizedDescription
        Task { await self?.markFailed(message) }
      case .cancelled:
        Task { await self?.markStopped() }
      default:
        break
      }
    }
    self.listener = listener
    listener.start(queue: queue)
  }

  public func stop() {
    listener?.cancel()
    listener = nil
    isListening = false
  }

  private func markReady() async {
    isListening = true
    if let assigned = listener?.port?.rawValue { port = assigned }
    await EventLog.shared.info("http", "listening on \(loopbackOnly ? "127.0.0.1" : "0.0.0.0"):\(port)")
  }

  private func markFailed(_ message: String) async {
    isListening = false
    await EventLog.shared.error("http", "listener failed: \(message)")
  }

  private func markStopped() {
    isListening = false
  }

  private func accept(_ handle: Handle) {
    handle.connection.start(queue: queue)
    Task { await serve(handle) }
  }

  private func serve(_ handle: Handle) async {
    let connection = handle.connection
    var buffer = Data()
    while true {
      guard let chunk = await receive(handle) else { break }
      buffer.append(chunk)
      // Refuse absurd bodies rather than letting a bad client grow the buffer
      // until the app is killed for memory.
      if buffer.count > 4_000_000 {
        await send(HTTPResponse.error(413, "request too large"), on: handle)
        break
      }
      guard let (request, consumed) = HTTPRequest.parse(buffer) else { continue }
      buffer.removeSubrange(buffer.startIndex..<buffer.index(buffer.startIndex, offsetBy: consumed))
      let response = await handler(request)
      await send(response, on: handle)
      if case .stream = response.body { return }
      break
    }
    connection.cancel()
  }

  private func receive(_ handle: Handle) async -> Data? {
    await withCheckedContinuation { continuation in
      handle.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
        if let data, !data.isEmpty {
          continuation.resume(returning: data)
        } else {
          continuation.resume(returning: (isComplete || error != nil) ? nil : Data())
        }
      }
    }
  }

  private func send(_ response: HTTPResponse, on handle: Handle) async {
    let connection = handle.connection
    await write(response.headerData(), on: handle)
    switch response.body {
    case .data(let data):
      if !data.isEmpty { await write(data, on: handle) }
      connection.cancel()
    case .stream(let stream):
      // The event stream owns the connection until the client goes away.
      for await frame in stream {
        await write(Data(frame.utf8), on: handle)
        if connection.state != .ready { break }
      }
      connection.cancel()
    }
  }

  private func write(_ data: Data, on handle: Handle) async {
    await withCheckedContinuation { continuation in
      handle.connection.send(content: data, completion: .contentProcessed { _ in
        continuation.resume()
      })
    }
  }
}
