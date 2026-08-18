//
//  StarkApp — minimal host app for the on-device server.
//
//  Drop this file into an iOS app target that depends on the StarkKit product
//  of this package. See README.md in this folder for the target settings.
//
import BackgroundTasks
import StarkKit
import SwiftUI

@main
struct StarkApp: App {
  @State private var server: StarkServer?
  @State private var failure: String?

  var body: some Scene {
    WindowGroup {
      Group {
        if let server {
          StarkDashboard(server: server)
        } else if let failure {
          Text(failure).font(.system(.footnote, design: .monospaced)).padding()
        } else {
          ProgressView().tint(.white)
        }
      }
      .background(.black)
      .preferredColorScheme(.dark)
      .task {
        do {
          // Boot without polling: nothing is connected on a fresh install, and
          // the loop should not start guessing before a model is loaded.
          let booted = try await Stark.boot(startEngine: false)
          await booted.seedIfEmpty(product: DigitalProduct(
            name: "Your product",
            pitch: "what it does, for whom",
            facts: ["runs offline", "one-time purchase"],
            limitations: ["no Windows build yet"],
            url: "https://example.com",
            keywords: ["render", "export"]
          ))
          StarkBackgroundRefresh.register(server: booted)
          StarkBackgroundRefresh.schedule()
          server = booted
        } catch {
          failure = error.localizedDescription
        }
      }
    }
  }
}
