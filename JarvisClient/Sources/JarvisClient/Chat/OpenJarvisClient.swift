//
//  JarvisClient
//
import Foundation

/// Errors surfaced when talking to an OpenJarvis server.
enum OpenJarvisError: LocalizedError {
  case invalidServerURL
  case http(Int)

  var errorDescription: String? {
    switch self {
    case .invalidServerURL:
      return "Set the OpenJarvis server address in Settings."
    case let .http(code):
      return "OpenJarvis server returned HTTP \(code). Is `jarvis serve` running on your Mac?"
    }
  }
}

/// Minimal client for OpenJarvis's OpenAI-compatible REST API
/// (`jarvis serve --host 0.0.0.0 --port 8000`):
///  - `GET  /health`
///  - `GET  /v1/models`
///  - `POST /v1/chat/completions` (streamed via Server-Sent Events)
struct OpenJarvisClient {
  /// Root server URL, e.g. `http://192.168.1.42:8000` (no trailing path).
  let rootURL: URL

  /// API key sent as `Authorization: Bearer <apiKey>` on `/v1/*` routes.
  /// OpenJarvis requires this whenever `jarvis serve` is bound to a
  /// non-loopback host (generate one with `jarvis auth create-key`).
  /// `/health` doesn't require it. May be empty.
  var apiKey: String = ""

  private struct OpenAIMessage: Encodable {
    let role: String
    let content: String
  }

  private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [OpenAIMessage]
    let stream: Bool
  }

  private struct ChatCompletionChunk: Decodable {
    struct Choice: Decodable {
      struct Delta: Decodable {
        let content: String?
      }
      let delta: Delta
    }
    let choices: [Choice]
  }

  private struct ModelsResponse: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
  }

  /// `true` if `/health` responds with HTTP 200.
  func checkHealth() async throws -> Bool {
    let (_, response) = try await URLSession.shared.data(from: rootURL.appendingPathComponent("health"))
    return (response as? HTTPURLResponse)?.statusCode == 200
  }

  /// Model identifiers reported by `/v1/models`.
  func availableModels() async throws -> [String] {
    var request = URLRequest(url: rootURL.appendingPathComponent("v1/models"))
    applyAuth(to: &request)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
      throw OpenJarvisError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
    }
    return try JSONDecoder().decode(ModelsResponse.self, from: data).data.map(\.id)
  }

  /// Adds the `Authorization: Bearer <apiKey>` header if an API key is set.
  private func applyAuth(to request: inout URLRequest) {
    guard !apiKey.isEmpty else { return }
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
  }

  /// Streams an assistant reply for `messages`, yielding text deltas as they arrive.
  func streamChatCompletion(model: String, messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          var request = URLRequest(url: rootURL.appendingPathComponent("v1/chat/completions"))
          request.httpMethod = "POST"
          request.setValue("application/json", forHTTPHeaderField: "Content-Type")
          applyAuth(to: &request)
          request.httpBody = try JSONEncoder().encode(
            ChatCompletionRequest(
              model: model,
              messages: messages.map { OpenAIMessage(role: $0.role.rawValue, content: $0.content) },
              stream: true
            )
          )

          let (bytes, response) = try await URLSession.shared.bytes(for: request)
          guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw OpenJarvisError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
          }

          for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8) else { continue }
            let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: data)
            if let content = chunk.choices.first?.delta.content, !content.isEmpty {
              continuation.yield(content)
            }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
