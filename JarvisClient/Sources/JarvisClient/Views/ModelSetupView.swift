//
//  JarvisClient
//
import SwiftUI
import UniformTypeIdentifiers

/// Lets the user fetch (or import) Kokoro's model weights and voice packs,
/// which are too large to bundle with the app.
struct ModelSetupView: View {
  @EnvironmentObject private var voiceModel: VoiceModelManager
  @Environment(\.dismiss) private var dismiss

  @State private var modelURLString = "https://huggingface.co/mlx-community/Kokoro-82M-bf16/resolve/main/kokoro-v1_0.safetensors"
  @State private var voicesURLString = ""
  @State private var showModelFileImporter = false
  @State private var showVoicesFileImporter = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text("Kokoro's voice model is large and isn't bundled with the app. Set it up once — it's cached on this device after that.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        Section("kokoro-v1_0.safetensors") {
          statusRow(present: voiceModel.isModelFilePresent)
          TextField("Download URL", text: $modelURLString)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          Button("Import from Files…") { showModelFileImporter = true }
        }

        Section("voices.npz") {
          statusRow(present: voiceModel.isVoicesFilePresent)
          Text("Generate this file on your Mac with JarvisClient/Scripts/build_voices_npz.py, then AirDrop it to your iPhone and import it below.")
            .font(.footnote)
            .foregroundStyle(.secondary)
          TextField("Download URL (optional)", text: $voicesURLString)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          Button("Import from Files…") { showVoicesFileImporter = true }
        }

        if case let .downloading(progress) = voiceModel.status {
          Section {
            ProgressView(value: progress)
            Text("Downloading…")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }

        if let errorMessage {
          Section {
            Text(errorMessage).foregroundStyle(.red)
          }
        }

        Section {
          Button("Download Now") {
            errorMessage = nil
            Task {
              let modelURL = voiceModel.isModelFilePresent ? nil : URL(string: modelURLString)
              let voicesURL = voiceModel.isVoicesFilePresent || voicesURLString.isEmpty
                ? nil : URL(string: voicesURLString)
              await voiceModel.download(modelURL: modelURL, voicesURL: voicesURL)
              if case let .failed(message) = voiceModel.status {
                errorMessage = message
              }
            }
          }
          .disabled(voiceModel.isReady)
        }

        if voiceModel.isReady {
          Section {
            Label("Voice model ready", systemImage: "checkmark.circle.fill")
              .foregroundStyle(.green)
          }
        }
      }
      .navigationTitle("Voice Model Setup")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .fileImporter(isPresented: $showModelFileImporter, allowedContentTypes: [.data]) { result in
        handleImport(result, isVoices: false)
      }
      .fileImporter(isPresented: $showVoicesFileImporter, allowedContentTypes: [.data]) { result in
        handleImport(result, isVoices: true)
      }
    }
  }

  @ViewBuilder
  private func statusRow(present: Bool) -> some View {
    Label(
      present ? "File present" : "Not downloaded yet",
      systemImage: present ? "checkmark.circle.fill" : "exclamationmark.circle"
    )
    .foregroundStyle(present ? .green : .secondary)
  }

  private func handleImport(_ result: Result<URL, Error>, isVoices: Bool) {
    do {
      let url = try result.get()
      if isVoices {
        try voiceModel.importVoicesFile(from: url)
      } else {
        try voiceModel.importModelFile(from: url)
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
