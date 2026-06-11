//
//  JarvisClient
//
import SwiftUI

@main
struct JarvisClientApp: App {
  @StateObject private var settings = AppSettings()
  @StateObject private var voiceModel = VoiceModelManager()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(settings)
        .environmentObject(voiceModel)
    }
  }
}
