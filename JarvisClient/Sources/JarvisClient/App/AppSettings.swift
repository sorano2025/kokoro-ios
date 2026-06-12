//
//  JarvisClient
//
import Foundation

/// User-configurable settings, persisted to `UserDefaults`.
///
/// `serverHost`/`serverPort` point at the machine running OpenJarvis
/// (`jarvis serve --host 0.0.0.0 --port 8000`) on the local network.
@MainActor
final class AppSettings: ObservableObject {
  static let defaultSystemPrompt = """
  You are Jarvis, a helpful personal assistant running locally for the user. \
  Keep replies concise and conversational, since they will be read aloud.
  """

  private enum Keys {
    static let serverHost = "jarvis.serverHost"
    static let serverPort = "jarvis.serverPort"
    static let apiKey = "jarvis.apiKey"
    static let modelName = "jarvis.modelName"
    static let systemPrompt = "jarvis.systemPrompt"
    static let selectedVoice = "jarvis.selectedVoice"
    static let speechRate = "jarvis.speechRate"
    static let speakResponses = "jarvis.speakResponses"
  }

  private let defaults = UserDefaults.standard

  /// IP address (or hostname) of the Mac running `jarvis serve`, e.g. "192.168.1.42".
  @Published var serverHost: String {
    didSet { defaults.set(serverHost, forKey: Keys.serverHost) }
  }

  /// Port OpenJarvis is serving on (default 8000).
  @Published var serverPort: Int {
    didSet { defaults.set(serverPort, forKey: Keys.serverPort) }
  }

  /// API key for OpenJarvis's `/v1/*` routes, sent as `Authorization: Bearer <key>`.
  /// Required whenever `jarvis serve` is bound to a non-loopback host (e.g.
  /// `--host 0.0.0.0`), which is the case for this app. Generate one on the
  /// Mac with `jarvis auth create-key`.
  @Published var apiKey: String {
    didSet { defaults.set(apiKey, forKey: Keys.apiKey) }
  }

  /// Model identifier passed to `/v1/chat/completions`, e.g. "qwen3:8b".
  @Published var modelName: String {
    didSet { defaults.set(modelName, forKey: Keys.modelName) }
  }

  /// System prompt prepended to every conversation.
  @Published var systemPrompt: String {
    didSet { defaults.set(systemPrompt, forKey: Keys.systemPrompt) }
  }

  /// Name of the Kokoro voice to use, e.g. "af_heart".
  @Published var selectedVoice: String {
    didSet { defaults.set(selectedVoice, forKey: Keys.selectedVoice) }
  }

  /// Kokoro speech speed multiplier (1.0 = normal).
  @Published var speechRate: Double {
    didSet { defaults.set(speechRate, forKey: Keys.speechRate) }
  }

  /// Whether assistant replies should be spoken aloud via Kokoro.
  @Published var speakResponses: Bool {
    didSet { defaults.set(speakResponses, forKey: Keys.speakResponses) }
  }

  init() {
    serverHost = defaults.string(forKey: Keys.serverHost) ?? ""
    serverPort = defaults.object(forKey: Keys.serverPort) as? Int ?? 8000
    apiKey = defaults.string(forKey: Keys.apiKey) ?? ""
    modelName = defaults.string(forKey: Keys.modelName) ?? "qwen3:8b"
    systemPrompt = defaults.string(forKey: Keys.systemPrompt) ?? AppSettings.defaultSystemPrompt
    selectedVoice = defaults.string(forKey: Keys.selectedVoice) ?? "af_heart"
    speechRate = defaults.object(forKey: Keys.speechRate) as? Double ?? 1.0
    speakResponses = defaults.object(forKey: Keys.speakResponses) as? Bool ?? true
  }

  /// Root URL of the OpenJarvis server, e.g. `http://192.168.1.42:8000`.
  /// `nil` until the user fills in a server address.
  var baseURL: URL? {
    let host = serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !host.isEmpty else { return nil }
    return URL(string: "http://\(host):\(serverPort)")
  }
}
