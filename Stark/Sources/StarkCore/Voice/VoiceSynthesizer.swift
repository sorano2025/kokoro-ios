//
//  StarkCore
//
import Foundation

/// Renders text to an audio file on the device.
///
/// Kept as a protocol because the obvious high-quality implementation —
/// Kokoro, the TTS engine in the parent repository — cannot currently link
/// alongside the LLM runtime: MisakiSwift pins mlx-swift to 0.30.2 while
/// mlx-swift-lm requires 0.30.3 or newer. `Examples/KokoroVoice` holds that
/// implementation, ready for the day the pins line up; `SystemVoice` is the
/// dependency-free stand-in that works today.
public protocol VoiceSynthesizer: Sendable {
  /// Speaks `text` and returns the file it was written to.
  func speak(_ text: String) async throws -> URL
}

public enum VoiceError: Error, LocalizedError {
  case synthesisFailed(String)

  public var errorDescription: String? {
    switch self {
    case .synthesisFailed(let detail): "Speech synthesis failed: \(detail)"
    }
  }
}
