//
//  JarvisClient
//
import SwiftUI

/// The main conversation screen: scrolling transcript, mic button and text input.
struct ChatView: View {
  @ObservedObject var conversation: ConversationViewModel
  @ObservedObject var synthesizer: KokoroVoiceSynthesizer
  @StateObject private var speechRecognizer = SpeechRecognizer()
  @FocusState private var inputFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(conversation.messages.filter { $0.role != .system }) { message in
              MessageBubbleView(message: message)
                .id(message.id)
            }
          }
          .padding()
        }
        .onChange(of: conversation.messages) { _, messages in
          guard let last = messages.last else { return }
          withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        }
      }

      if let errorMessage = conversation.errorMessage {
        Text(errorMessage)
          .font(.footnote)
          .foregroundStyle(.red)
          .padding(.horizontal)
          .padding(.bottom, 4)
      }

      if speechRecognizer.isRecording {
        Text(speechRecognizer.transcript.isEmpty ? "Listening…" : speechRecognizer.transcript)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .padding(.horizontal)
          .padding(.bottom, 4)
      } else if synthesizer.isSpeaking {
        Label("Speaking…", systemImage: "speaker.wave.2.fill")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .padding(.horizontal)
          .padding(.bottom, 4)
      }

      HStack(spacing: 12) {
        TextField("Message Jarvis…", text: $conversation.inputText, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .focused($inputFocused)
          .lineLimit(1...4)
          .onSubmit(send)

        MicButtonView(speechRecognizer: speechRecognizer) { transcript in
          conversation.inputText = transcript
          send()
        }

        Button(action: send) {
          Image(systemName: "arrow.up.circle.fill")
            .font(.system(size: 28))
        }
        .disabled(conversation.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || conversation.isProcessing)
      }
      .padding()
    }
  }

  private func send() {
    inputFocused = false
    conversation.send(conversation.inputText)
  }
}
