//
//  StarkLLM
//
import Foundation
import KokoroSwift
import MLX
import StarkCore

/// Speaks a draft with the on-device Kokoro TTS that ships in this repo.
///
/// Voice notes and short audio clips outperform text on several of the
/// platforms this server connects to, and since the text never leaves the phone
/// there is no reason for the audio to either. The model path and voice
/// embedding come from the host app, exactly as `KokoroTTS` expects.
public actor KokoroVoice {
  private let tts: KokoroTTS
  private let voice: MLXArray
  private let language: Language

  public init(modelPath: URL, voice: MLXArray, language: Language = .enUS) {
    self.tts = KokoroTTS(modelPath: modelPath, g2p: .misaki)
    self.voice = voice
    self.language = language
  }

  /// Renders `text` to a WAV file and returns its path.
  ///
  /// Kokoro caps input length, so long drafts are spoken in sentence-sized
  /// chunks and concatenated rather than refused.
  public func speak(_ text: String, speed: Float = 1.0) throws -> URL {
    var samples: [Float] = []
    for chunk in TextChunker.chunk(text) {
      let (audio, _) = try tts.generateAudio(voice: voice, language: language, text: chunk, speed: speed)
      samples.append(contentsOf: audio)
    }
    let url = StarkPaths.file("voice-\(UUID().uuidString.prefix(8)).wav")
    try AudioUtils.writeWavFile(samples: samples, sampleRate: 24000, fileURL: url)
    return url
  }

}
