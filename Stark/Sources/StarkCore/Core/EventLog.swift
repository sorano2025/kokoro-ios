//
//  StarkCore
//
import Foundation
import os

/// Severity of a log line, mirrored into the dashboard's colour coding.
public enum LogLevel: String, Codable, Sendable, CaseIterable {
  case debug, info, warn, error
}

public struct LogEntry: Codable, Sendable, Identifiable, Equatable {
  public let id: UUID
  public let at: Date
  public let level: LogLevel
  public let source: String
  public let message: String

  public init(level: LogLevel, source: String, message: String) {
    self.id = UUID()
    self.at = Date()
    self.level = level
    self.source = source
    self.message = message
  }
}

/// In-memory ring buffer that backs both `/api/logs` and the SwiftUI log pane.
///
/// Lines also go to `os.Logger` so they show up in Console.app when the phone
/// is tethered, but the ring buffer is what the on-device UI reads: it needs
/// the history, and unified logging cannot be read back from inside the app.
public actor EventLog {
  public static let shared = EventLog()

  private let logger = Logger(subsystem: "stark.server", category: "core")
  private var entries: [LogEntry] = []
  private let capacity = 500
  private var continuations: [UUID: AsyncStream<LogEntry>.Continuation] = [:]

  public func log(_ level: LogLevel, _ source: String, _ message: String) {
    let entry = LogEntry(level: level, source: source, message: message)
    entries.append(entry)
    if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    switch level {
    case .debug: logger.debug("[\(source, privacy: .public)] \(message, privacy: .public)")
    case .info: logger.info("[\(source, privacy: .public)] \(message, privacy: .public)")
    case .warn: logger.warning("[\(source, privacy: .public)] \(message, privacy: .public)")
    case .error: logger.error("[\(source, privacy: .public)] \(message, privacy: .public)")
    }
    for continuation in continuations.values { continuation.yield(entry) }
  }

  public func debug(_ source: String, _ message: String) { log(.debug, source, message) }
  public func info(_ source: String, _ message: String) { log(.info, source, message) }
  public func warn(_ source: String, _ message: String) { log(.warn, source, message) }
  public func error(_ source: String, _ message: String) { log(.error, source, message) }

  public func recent(limit: Int = 200) -> [LogEntry] {
    Array(entries.suffix(limit).reversed())
  }

  /// Live tail used by the dashboard's server-sent-events endpoint.
  public func stream() -> AsyncStream<LogEntry> {
    AsyncStream { continuation in
      let id = UUID()
      continuations[id] = continuation
      continuation.onTermination = { [weak self] _ in
        Task { await self?.removeStream(id) }
      }
    }
  }

  private func removeStream(_ id: UUID) {
    continuations[id] = nil
  }
}
