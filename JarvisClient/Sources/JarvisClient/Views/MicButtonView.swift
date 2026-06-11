//
//  JarvisClient
//
import SwiftUI

/// Push-to-talk microphone button. Tap to start listening, tap again to stop
/// and report the transcript via `onFinish`.
struct MicButtonView: View {
  @ObservedObject var speechRecognizer: SpeechRecognizer
  var onFinish: (String) -> Void

  var body: some View {
    Button(action: toggle) {
      Image(systemName: speechRecognizer.isRecording ? "mic.fill" : "mic")
        .font(.system(size: 22))
        .foregroundStyle(speechRecognizer.isRecording ? Color.red : Color.accentColor)
        .frame(width: 32, height: 32)
    }
  }

  private func toggle() {
    if speechRecognizer.isRecording {
      let transcript = speechRecognizer.transcript
      speechRecognizer.stopRecording()
      if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        onFinish(transcript)
      }
    } else {
      Task {
        guard await speechRecognizer.requestAuthorization() else { return }
        try? speechRecognizer.startRecording()
      }
    }
  }
}
