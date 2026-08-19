//
//  StarkKit
//
@_exported import StarkCore
@_exported import StarkLLM
@_exported import StarkUI
import Foundation

/// One call to get everything running.
///
/// ```swift
/// let server = try await Stark.boot()
/// StarkDashboard(server: server)
/// ```
public enum Stark {
  /// Creates the MLX runtime, boots the control server and starts the loop.
  /// - Parameter startEngine: pass `false` to boot the server without polling,
  ///   e.g. on first launch before anything is connected.
  @MainActor
  @discardableResult
  public static func boot(startEngine: Bool = true) async throws -> StarkServer {
    let server = StarkServer(model: MLXLanguageModel())
    try await server.start(startEngine: startEngine)
    return server
  }
}
