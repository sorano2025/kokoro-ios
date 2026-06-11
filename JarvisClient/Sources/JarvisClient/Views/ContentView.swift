//
//  JarvisClient
//
import SwiftUI

/// App root: wires up the conversation view model and shows the voice model
/// setup sheet on first launch if Kokoro's model files aren't ready yet.
struct ContentView: View {
  @EnvironmentObject private var settings: AppSettings
  @EnvironmentObject private var voiceModel: VoiceModelManager
  @StateObject private var synthesizer = KokoroVoiceSynthesizer()

  @State private var conversation: ConversationViewModel?
  @State private var showSettings = false
  @State private var showModelSetup = false

  var body: some View {
    NavigationStack {
      Group {
        if let conversation {
          ChatView(conversation: conversation, synthesizer: synthesizer)
        } else {
          ProgressView()
        }
      }
      .navigationTitle("Jarvis")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            showSettings = true
          } label: {
            Image(systemName: "gearshape")
          }
        }
      }
    }
    .sheet(isPresented: $showSettings) {
      SettingsView()
    }
    .sheet(isPresented: $showModelSetup, onDismiss: prepareVoiceEngineIfReady) {
      ModelSetupView()
    }
    .task {
      if conversation == nil {
        conversation = ConversationViewModel(settings: settings, voiceModel: voiceModel, synthesizer: synthesizer)
      }
      voiceModel.refreshStatus()
      if voiceModel.isReady {
        prepareVoiceEngineIfReady()
      } else {
        showModelSetup = true
      }
    }
  }

  private func prepareVoiceEngineIfReady() {
    guard voiceModel.isReady else { return }
    if !synthesizer.isLoaded {
      synthesizer.loadEngine(modelPath: voiceModel.modelFileURL)
    }
    Task {
      await voiceModel.loadVoicesIfNeeded()
    }
  }
}
