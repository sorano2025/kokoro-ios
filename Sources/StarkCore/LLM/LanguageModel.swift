//
//  StarkCore
//
import Foundation

/// One turn in a chat template.
public struct ChatMessage: Codable, Sendable, Equatable {
  public enum Role: String, Codable, Sendable { case system, user, assistant }
  public let role: Role
  public let content: String

  public init(_ role: Role, _ content: String) {
    self.role = role
    self.content = content
  }
}

/// What the runtime reports about the currently loaded weights.
public struct ModelStatus: Codable, Sendable, Equatable {
  public enum State: String, Codable, Sendable { case empty, downloading, loading, ready, failed }
  public var state: State
  public var modelID: String?
  /// 0...1 while downloading.
  public var progress: Double
  public var detail: String?
  /// Resident weight size once loaded, in bytes.
  public var weightBytes: Int64?
  public var loadedAt: Date?

  public init(state: State = .empty, modelID: String? = nil, progress: Double = 0, detail: String? = nil, weightBytes: Int64? = nil, loadedAt: Date? = nil) {
    self.state = state
    self.modelID = modelID
    self.progress = progress
    self.detail = detail
    self.weightBytes = weightBytes
    self.loadedAt = loadedAt
  }
}

/// The generation surface the automation layer codes against.
///
/// Kept protocol-shaped so `StarkCore` — the server, scheduler and guardrails —
/// carries no MLX dependency and can be unit tested on any machine with a stub
/// model. `StarkLLM` supplies the real MLX-backed implementation.
public protocol LanguageModel: Actor {
  var status: ModelStatus { get }
  /// Downloads if needed, then loads weights into memory.
  func load(modelID: String, onProgress: @Sendable @escaping (Double, String) -> Void) async throws
  func unload()
  /// Streams generated text. The returned stream finishes when the model stops.
  func generate(messages: [ChatMessage], options: SamplingOptions) async throws -> AsyncThrowingStream<String, Error>
}

public extension LanguageModel {
  /// Convenience wrapper that collects a full response and reports throughput.
  func complete(messages: [ChatMessage], options: SamplingOptions) async throws -> (text: String, tokensPerSecond: Double, tokens: Int) {
    let started = Date()
    var text = ""
    var chunks = 0
    for try await chunk in try await generate(messages: messages, options: options) {
      text += chunk
      chunks += 1
    }
    let elapsed = max(0.001, Date().timeIntervalSince(started))
    return (text, Double(chunks) / elapsed, chunks)
  }
}

public enum ModelError: Error, LocalizedError {
  case noModelLoaded
  case notEnoughMemory(needGB: Double, haveGB: Double)
  case notEnoughDisk(needGB: Double, haveGB: Double)
  case downloadFailed(String)
  case generationFailed(String)

  public var errorDescription: String? {
    switch self {
    case .noModelLoaded: "No model is loaded"
    case .notEnoughMemory(let need, let have):
      String(format: "Model needs ~%.1f GB of RAM, %.1f GB available to this app", need, have)
    case .notEnoughDisk(let need, let have):
      String(format: "Model needs %.1f GB on disk, %.1f GB free", need, have)
    case .downloadFailed(let detail): "Download failed: \(detail)"
    case .generationFailed(let detail): "Generation failed: \(detail)"
    }
  }
}
