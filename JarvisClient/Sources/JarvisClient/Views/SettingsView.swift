//
//  JarvisClient
//
import SwiftUI

/// Configuration for the OpenJarvis server connection and Kokoro voice.
struct SettingsView: View {
  @EnvironmentObject private var settings: AppSettings
  @EnvironmentObject private var voiceModel: VoiceModelManager
  @Environment(\.dismiss) private var dismiss

  @State private var connectionStatus: String?
  @State private var showModelSetup = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Mac's IP address, e.g. 192.168.1.42", text: $settings.serverHost)
            .keyboardType(.numbersAndPunctuation)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          Stepper("Port: \(settings.serverPort)", value: $settings.serverPort, in: 1...65535)
          SecureField("API key (oj_sk_...)", text: $settings.apiKey)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          TextField("Model name, e.g. qwen3:8b", text: $settings.modelName)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          Button("Test Connection", action: testConnection)
          if let connectionStatus {
            Text(connectionStatus)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        } header: {
          Text("OpenJarvis Server")
        } footer: {
          Text("Run `jarvis serve --host 0.0.0.0 --port 8000` on your Mac, enter its local network IP address here, and paste the key from `jarvis auth create-key`.")
        }

        Section("Voice") {
          if voiceModel.availableVoices.isEmpty {
            Text("No voice packs loaded yet.")
              .foregroundStyle(.secondary)
          } else {
            Picker("Voice", selection: $settings.selectedVoice) {
              ForEach(voiceModel.availableVoices, id: \.self) { voice in
                Text(voice).tag(voice)
              }
            }
          }

          Toggle("Speak responses aloud", isOn: $settings.speakResponses)

          VStack(alignment: .leading) {
            Text("Speech rate: \(settings.speechRate, specifier: "%.2f")x")
            Slider(value: $settings.speechRate, in: 0.5...2.0, step: 0.05)
          }

          Button("Manage Voice Model…") {
            showModelSetup = true
          }
        }

        Section("System Prompt") {
          TextEditor(text: $settings.systemPrompt)
            .frame(minHeight: 100)
        }
      }
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(isPresented: $showModelSetup) {
        ModelSetupView()
      }
    }
  }

  private func testConnection() {
    guard let baseURL = settings.baseURL else {
      connectionStatus = "Enter your Mac's IP address first."
      return
    }
    connectionStatus = "Checking…"
    Task {
      let client = OpenJarvisClient(rootURL: baseURL, apiKey: settings.apiKey)
      do {
        let healthy = try await client.checkHealth()
        guard healthy else {
          connectionStatus = "Server responded, but /health didn't return 200."
          return
        }
        // /v1/models requires the API key, so this also validates it.
        let models = try await client.availableModels()
        connectionStatus = models.isEmpty
          ? "Connected to OpenJarvis, but it reported no models."
          : "Connected to OpenJarvis. Models: \(models.joined(separator: ", "))"
      } catch OpenJarvisError.http(401) {
        connectionStatus = "Connected, but the API key is missing or incorrect. Run `jarvis auth create-key` on your Mac and paste it here."
      } catch {
        connectionStatus = error.localizedDescription
      }
    }
  }
}
