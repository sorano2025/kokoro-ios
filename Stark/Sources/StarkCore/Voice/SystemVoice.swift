//
//  StarkCore
//
import AVFoundation
import Foundation

/// `VoiceSynthesizer` on top of AVSpeechSynthesizer.
///
/// Ships with the OS, needs no download and no dependency, which makes it the
/// right default for a server whose whole point is running unattended on a
/// phone. Quality is below Kokoro's, so treat it as the floor rather than the
/// ceiling.
public final class SystemVoice: VoiceSynthesizer, @unchecked Sendable {
  private let synthesizer = AVSpeechSynthesizer()
  private let voiceIdentifier: String?
  private let rate: Float

  public init(voiceIdentifier: String? = nil, rate: Float = AVSpeechUtteranceDefaultSpeechRate) {
    self.voiceIdentifier = voiceIdentifier
    self.rate = rate
  }

  /// Every installed voice, for a picker in the host app.
  public static func availableVoices() -> [(identifier: String, name: String, language: String)] {
    AVSpeechSynthesisVoice.speechVoices().map { ($0.identifier, $0.name, $0.language) }
  }

  public func speak(_ text: String) async throws -> URL {
    let url = StarkPaths.file("voice-\(UUID().uuidString.prefix(8)).caf")
    let sink = AudioSink(url: url)

    let utterance = AVSpeechUtterance(string: text)
    utterance.rate = rate
    if let voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
      utterance.voice = voice
    }

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      // The callback arrives on an arbitrary queue and fires once per buffer,
      // ending with an empty one. The sink serialises the file writes and makes
      // sure the continuation resumes exactly once.
      synthesizer.write(utterance) { buffer in
        sink.accept(buffer, finish: { result in
          continuation.resume(with: result)
        })
      }
    }
    return url
  }
}

/// Collects synthesis buffers into one audio file.
private final class AudioSink: @unchecked Sendable {
  private let url: URL
  private let lock = NSLock()
  private var file: AVAudioFile?
  private var settled = false

  init(url: URL) {
    self.url = url
  }

  func accept(_ buffer: AVAudioBuffer, finish: (Result<Void, Error>) -> Void) {
    lock.lock()
    defer { lock.unlock() }
    guard !settled, let pcm = buffer as? AVAudioPCMBuffer else { return }

    // A zero-length buffer is how AVSpeechSynthesizer signals the end.
    guard pcm.frameLength > 0 else {
      settled = true
      file = nil
      finish(.success(()))
      return
    }

    do {
      if file == nil {
        file = try AVAudioFile(forWriting: url, settings: pcm.format.settings)
      }
      try file?.write(from: pcm)
    } catch {
      settled = true
      file = nil
      finish(.failure(VoiceError.synthesisFailed(error.localizedDescription)))
    }
  }
}
