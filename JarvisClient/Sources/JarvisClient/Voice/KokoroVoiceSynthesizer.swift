//
//  JarvisClient
//
import AVFoundation
import Foundation
import KokoroSwift
import MLX

/// Wraps `KokoroTTS` to turn assistant text into spoken audio, played back
/// through an `AVAudioEngine`.
@MainActor
final class KokoroVoiceSynthesizer: ObservableObject {
  @Published private(set) var isSpeaking = false

  private var tts: KokoroTTS?
  private let audioEngine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private var isEngineRunning = false

  var isLoaded: Bool { tts != nil }

  /// Loads the Kokoro model weights from disk. Call once the model file is available.
  func loadEngine(modelPath: URL) {
    tts = KokoroTTS(modelPath: modelPath, g2p: .misaki)
  }

  /// Splits `text` into speakable chunks, synthesizes each with Kokoro and
  /// plays them back in order. Voice names starting with "a" use US English,
  /// everything else uses GB English (matching Kokoro's voice naming convention).
  func speak(text: String, voiceEmbedding: MLXArray, voiceName: String, speed: Float) async throws {
    guard let tts else { return }
    let language: Language = voiceName.hasPrefix("a") ? .enUS : .enGB

    for chunk in Self.splitIntoChunks(text) {
      let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }

      let (samples, _) = try await Task.detached {
        try tts.generateAudio(voice: voiceEmbedding, language: language, text: trimmed, speed: speed)
      }.value

      try await play(samples: samples)
    }
  }

  /// Stops any in-flight playback immediately.
  func stop() {
    playerNode.stop()
    isSpeaking = false
  }

  private func play(samples: [Float]) async throws {
    guard !samples.isEmpty else { return }
    guard let format = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: Double(KokoroTTS.Constants.samplingRate),
      channels: 1,
      interleaved: false
    ) else { return }

    if !isEngineRunning {
      audioEngine.attach(playerNode)
      audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
      try audioEngine.start()
      isEngineRunning = true
    }

    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
      return
    }
    buffer.frameLength = buffer.frameCapacity
    samples.withUnsafeBufferPointer { source in
      buffer.floatChannelData?[0].update(from: source.baseAddress!, count: samples.count)
    }

    isSpeaking = true
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
        continuation.resume()
      }
      if !playerNode.isPlaying {
        playerNode.play()
      }
    }
    isSpeaking = false
  }

  /// Splits text on sentence-ending punctuation so each request to Kokoro stays
  /// well under its ~510 token limit and audio can start playing sooner.
  private static func splitIntoChunks(_ text: String) -> [String] {
    let sentenceEnders: Set<Character> = [".", "!", "?", "\n"]
    var chunks: [String] = []
    var current = ""

    for character in text {
      current.append(character)
      if sentenceEnders.contains(character) {
        chunks.append(current)
        current = ""
      }
    }
    if !current.isEmpty {
      chunks.append(current)
    }
    return chunks
  }
}
