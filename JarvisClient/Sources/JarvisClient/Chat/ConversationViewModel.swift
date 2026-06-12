//
//  JarvisClient
//
import Foundation

/// Orchestrates a turn of conversation: sends the user's message (plus history)
/// to OpenJarvis, streams the reply into the transcript, and speaks completed
/// sentences aloud via Kokoro as they arrive.
@MainActor
final class ConversationViewModel: ObservableObject {
  @Published var messages: [ChatMessage] = []
  @Published var inputText: String = ""
  @Published private(set) var isProcessing: Bool = false
  @Published var errorMessage: String?

  private let settings: AppSettings
  private let voiceModel: VoiceModelManager
  private let synthesizer: KokoroVoiceSynthesizer

  init(settings: AppSettings, voiceModel: VoiceModelManager, synthesizer: KokoroVoiceSynthesizer) {
    self.settings = settings
    self.voiceModel = voiceModel
    self.synthesizer = synthesizer
  }

  /// Sends `text` as a user message and streams back Jarvis's reply.
  func send(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !isProcessing else { return }

    guard let baseURL = settings.baseURL else {
      errorMessage = OpenJarvisError.invalidServerURL.localizedDescription
      return
    }

    errorMessage = nil
    inputText = ""
    messages.append(ChatMessage(role: .user, content: trimmed))

    let assistantID = UUID()
    messages.append(ChatMessage(id: assistantID, role: .assistant, content: ""))

    let history = [ChatMessage(role: .system, content: settings.systemPrompt)]
      + messages.filter { $0.id != assistantID }
    let client = OpenJarvisClient(rootURL: baseURL, apiKey: settings.apiKey)
    let model = settings.modelName
    let voiceName = settings.selectedVoice
    let speed = Float(settings.speechRate)
    let shouldSpeak = settings.speakResponses && synthesizer.isLoaded
    let voiceEmbedding = shouldSpeak ? voiceModel.voiceEmbedding(named: voiceName) : nil

    isProcessing = true
    Task {
      var speechBuffer = ""
      do {
        for try await delta in client.streamChatCompletion(model: model, messages: history) {
          append(delta, toMessageWithID: assistantID)

          if let voiceEmbedding {
            speechBuffer += delta
            let (toSpeak, remainder) = Self.extractCompleteSentences(from: speechBuffer)
            if !toSpeak.isEmpty {
              speechBuffer = remainder
              try? await synthesizer.speak(text: toSpeak, voiceEmbedding: voiceEmbedding, voiceName: voiceName, speed: speed)
            }
          }
        }

        if let voiceEmbedding, !speechBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          try? await synthesizer.speak(text: speechBuffer, voiceEmbedding: voiceEmbedding, voiceName: voiceName, speed: speed)
        }
      } catch {
        errorMessage = error.localizedDescription
      }
      isProcessing = false
    }
  }

  private func append(_ delta: String, toMessageWithID id: UUID) {
    guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
    messages[index].content += delta
  }

  /// Splits off any text up to and including the last sentence-ending
  /// punctuation, returning `(speakable, remainder)`.
  private static func extractCompleteSentences(from text: String) -> (toSpeak: String, remainder: String) {
    guard let lastEnder = text.lastIndex(where: { ".!?\n".contains($0) }) else {
      return ("", text)
    }
    let toSpeak = String(text[...lastEnder])
    let remainder = String(text[text.index(after: lastEnder)...])
    return (toSpeak, remainder)
  }
}
