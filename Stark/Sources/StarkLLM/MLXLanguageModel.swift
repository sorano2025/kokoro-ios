//
//  StarkLLM
//
import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import StarkCore

/// `LanguageModel` backed by MLX, running the weights on the phone's GPU.
///
/// Everything MLX-shaped is confined to this file. `mlx-swift-lm` moves fast,
/// so when its generation API shifts there is exactly one place to follow it,
/// and the rest of the server keeps compiling.
public actor MLXLanguageModel: StarkCore.LanguageModel {
  public private(set) var status = ModelStatus()
  private var container: ModelContainer?

  public init() {}

  public func load(modelID: String, onProgress: @Sendable @escaping (Double, String) -> Void) async throws {
    if status.modelID == modelID, status.state == .ready { return }

    if let descriptor = ModelCatalog.descriptor(for: modelID) {
      try DeviceCapability.check(descriptor)
    }

    // A phone will hand the GPU cache as much as it asks for and then get
    // jetsammed for it. Capping the cache keeps the resident set close to the
    // weights themselves.
    MLX.GPU.set(cacheLimit: 32 * 1024 * 1024)

    container = nil
    status = ModelStatus(state: .downloading, modelID: modelID, progress: 0, detail: "fetching weights")

    do {
      let configuration = ModelConfiguration(id: modelID)
      // The default hub cache is used deliberately: it is the location the
      // factory resumes partial downloads from, and `StarkPaths.models` points
      // at the same directory so size reporting and the backup-exclusion flag
      // follow the weights.
      let loaded = try await LLMModelFactory.shared.loadContainer(
        configuration: configuration
      ) { progress in
        onProgress(progress.fractionCompleted, progress.localizedDescription ?? "downloading")
        Task { [weak self] in await self?.note(progress: progress.fractionCompleted) }
      }
      status = ModelStatus(state: .loading, modelID: modelID, progress: 1, detail: "loading weights")
      container = loaded
      let bytes = try? FileManager.default.allocatedSizeOfDirectory(at: StarkPaths.models)
      status = ModelStatus(state: .ready, modelID: modelID, progress: 1, detail: nil, weightBytes: bytes, loadedAt: Date())
    } catch {
      status = ModelStatus(state: .failed, modelID: modelID, progress: 0, detail: error.localizedDescription)
      throw ModelError.downloadFailed(error.localizedDescription)
    }
  }

  private func note(progress: Double) {
    guard status.state == .downloading else { return }
    status.progress = progress
  }

  public func unload() {
    container = nil
    status = ModelStatus()
    MLX.GPU.clearCache()
  }

  public func generate(messages: [ChatMessage], options: SamplingOptions) async throws -> AsyncThrowingStream<String, Error> {
    guard let container else { throw ModelError.noModelLoaded }

    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          // `messages` and `options` are Sendable value types; `Chat.Message`
          // and `GenerateParameters` are built inside the model's isolation so
          // nothing non-Sendable crosses the boundary.
          try await container.perform { context in
            let chat: [Chat.Message] = messages.map { message in
              switch message.role {
              case .system: .system(message.content)
              case .user: .user(message.content)
              case .assistant: .assistant(message.content)
              }
            }
            let parameters = GenerateParameters(
              maxTokens: options.maxTokens,
              temperature: options.temperature,
              topP: options.topP,
              repetitionPenalty: options.repetitionPenalty
            )
            let input = try await context.processor.prepare(input: UserInput(chat: chat))
            var emitted = ""
            _ = try MLXLMCommon.generate(input: input, parameters: parameters, context: context) { tokens in
              // The callback hands back every token so far; only the tail is
              // new, and detokenising the whole prefix each time is how the
              // decoder keeps multi-token characters intact.
              let text = context.tokenizer.decode(tokens: tokens)
              if text.count > emitted.count {
                continuation.yield(String(text.dropFirst(emitted.count)))
                emitted = text
              }
              return tokens.count >= options.maxTokens ? .stop : .more
            }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: ModelError.generationFailed(error.localizedDescription))
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

extension FileManager {
  /// Total bytes actually on disk under a directory, used to report the size
  /// of the downloaded weights.
  func allocatedSizeOfDirectory(at url: URL) throws -> Int64 {
    guard let enumerator = enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
    var total: Int64 = 0
    for case let fileURL as URL in enumerator {
      let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
      total += Int64(values?.totalFileAllocatedSize ?? 0)
    }
    return total
  }
}
