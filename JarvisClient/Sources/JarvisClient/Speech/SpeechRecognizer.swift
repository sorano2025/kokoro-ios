//
//  JarvisClient
//
import AVFoundation
import Foundation
import Speech

/// On-device push-to-talk speech recognition using `SFSpeechRecognizer`.
@MainActor
final class SpeechRecognizer: ObservableObject {
  enum RecognizerError: LocalizedError {
    case notAuthorized
    case recognizerUnavailable

    var errorDescription: String? {
      switch self {
      case .notAuthorized:
        return "Speech recognition isn't authorized. Enable it in Settings > Privacy."
      case .recognizerUnavailable:
        return "Speech recognition isn't available on this device right now."
      }
    }
  }

  @Published private(set) var transcript = ""
  @Published private(set) var isRecording = false

  private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
  private let audioEngine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?

  /// Requests microphone + speech recognition permission. Safe to call repeatedly.
  func requestAuthorization() async -> Bool {
    let speechStatus = await SFSpeechRecognizer.requestAuthorization()
    let micGranted = await AVAudioApplication.requestRecordPermission()
    return speechStatus == .authorized && micGranted
  }

  func startRecording() throws {
    guard let recognizer, recognizer.isAvailable else {
      throw RecognizerError.recognizerUnavailable
    }

    stopRecording()

    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
    try session.setActive(true, options: .notifyOthersOnDeactivation)

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    if recognizer.supportsOnDeviceRecognition {
      request.requiresOnDeviceRecognition = true
    }
    self.request = request

    let inputNode = audioEngine.inputNode
    let format = inputNode.outputFormat(forBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
      request.append(buffer)
    }

    audioEngine.prepare()
    try audioEngine.start()

    transcript = ""
    isRecording = true

    task = recognizer.recognitionTask(with: request) { [weak self] result, error in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if let result {
          self.transcript = result.bestTranscription.formattedString
        }
        if error != nil || result?.isFinal == true {
          self.stopRecording()
        }
      }
    }
  }

  func stopRecording() {
    guard isRecording else { return }
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)
    request?.endAudio()
    task?.cancel()
    request = nil
    task = nil
    isRecording = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}
