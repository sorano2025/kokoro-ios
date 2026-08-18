//
//  StarkKit
//
#if os(iOS)
import BackgroundTasks
import Foundation
import StarkCore

/// Keeps the loop ticking when the app is not in the foreground.
///
/// iOS suspends the process within seconds of backgrounding, so the in-app
/// timer stops with it. `BGProcessingTask` is the sanctioned way back in: the
/// system decides when, usually while charging on Wi-Fi, and hands over a few
/// minutes — enough for one poll-draft-queue pass. Anything needing tighter
/// timing has to run with the app open, which is what the "run now" button and
/// the loopback console are for.
public enum StarkBackgroundRefresh {
  public static let taskID = "stark.server.refresh"

  /// Call from `application(_:didFinishLaunchingWithOptions:)` — registration
  /// after launch is a hard error on iOS.
  @MainActor
  public static func register(server: StarkServer) {
    // Registered on the main queue so the handler can stay on the same
    // isolation as the server it drives; `BGTask` is not Sendable and must not
    // be passed across domains.
    BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: .main) { task in
      MainActor.assumeIsolated {
        guard let task = task as? BGProcessingTask else { return }
        let work = Task { @MainActor in
          let drafted = await server.runBackgroundPass()
          await EventLog.shared.info("background", "pass complete, \(drafted) drafted")
          schedule()
          task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
          work.cancel()
          Task { await EventLog.shared.warn("background", "pass expired before finishing") }
        }
      }
    }
  }

  /// Ask for the next window. Requires the identifier in the target's
  /// `BGTaskSchedulerPermittedIdentifiers` and the `processing` background mode.
  public static func schedule(earliestIn seconds: TimeInterval = 15 * 60) {
    let request = BGProcessingTaskRequest(identifier: taskID)
    request.earliestBeginDate = Date(timeIntervalSinceNow: seconds)
    // Model inference is heavy enough that the system should only wake us when
    // running it will not cost the user their battery.
    request.requiresExternalPower = true
    request.requiresNetworkConnectivity = true
    try? BGTaskScheduler.shared.submit(request)
  }
}
#endif
