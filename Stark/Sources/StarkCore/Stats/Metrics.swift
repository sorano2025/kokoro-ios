//
//  StarkCore
//
import Foundation

/// A single recorded action. Kept as an append-only trail because both the
/// rate limiter and the dashboard need to ask "what happened in the last N
/// minutes", and a counter cannot answer that.
public struct MetricEvent: Codable, Sendable, Equatable {
  public enum Kind: String, Codable, Sendable, CaseIterable {
    case fetched, drafted, queued, approved, rejected, sent, blocked, failed
  }
  public let kind: Kind
  public let at: Date
  public let connectionID: String?
  public let threadID: String?
  /// Generated tokens for `drafted`, latency in ms for `sent`.
  public let value: Double?

  public init(kind: Kind, at: Date = Date(), connectionID: String? = nil, threadID: String? = nil, value: Double? = nil) {
    self.kind = kind
    self.at = at
    self.connectionID = connectionID
    self.threadID = threadID
    self.value = value
  }
}

/// What the dashboard renders.
public struct MetricsSnapshot: Codable, Sendable, Equatable {
  public var counts: [String: Int]
  public var last24h: [String: Int]
  public var perConnectionSent24h: [String: Int]
  /// 24 hourly buckets, oldest first, of drafts sent.
  public var sentByHour: [Int]
  public var tokensPerSecond: Double
  public var averageDraftTokens: Double
  public var uptimeSeconds: Double
  public var queueDepth: Int
  public var startedAt: Date

  public init(
    counts: [String: Int] = [:],
    last24h: [String: Int] = [:],
    perConnectionSent24h: [String: Int] = [:],
    sentByHour: [Int] = Array(repeating: 0, count: 24),
    tokensPerSecond: Double = 0,
    averageDraftTokens: Double = 0,
    uptimeSeconds: Double = 0,
    queueDepth: Int = 0,
    startedAt: Date = Date()
  ) {
    self.counts = counts
    self.last24h = last24h
    self.perConnectionSent24h = perConnectionSent24h
    self.sentByHour = sentByHour
    self.tokensPerSecond = tokensPerSecond
    self.averageDraftTokens = averageDraftTokens
    self.uptimeSeconds = uptimeSeconds
    self.queueDepth = queueDepth
    self.startedAt = startedAt
  }
}

/// Rolling metric store.
///
/// Events older than seven days are dropped on write: this runs on a phone,
/// and an unbounded trail would grow until the next storage-pressure eviction
/// took the whole container with it.
public actor MetricsStore {
  private var events: [MetricEvent] = []
  private var throughputSamples: [Double] = []
  private let store = JSONStore<[MetricEvent]>(filename: "metrics.json") { [] }
  private let startedAt = Date()
  private var loaded = false
  private let retention: TimeInterval = 7 * 24 * 3600

  public init() {}

  private func loadIfNeeded() {
    loaded = true
  }

  public func hydrate() async {
    loaded = true
    events = await store.load()
    prune()
  }

  public func record(_ event: MetricEvent) async {
    loadIfNeeded()
    events.append(event)
    prune()
    let snapshot = events
    await store.save(snapshot)
  }

  /// Tokens per second from the most recent generations, capped to a short
  /// window so the number tracks the model currently loaded.
  public func recordThroughput(tokensPerSecond: Double) {
    throughputSamples.append(tokensPerSecond)
    if throughputSamples.count > 20 { throughputSamples.removeFirst() }
  }

  public func count(_ kind: MetricEvent.Kind, since: Date? = nil, connectionID: String? = nil, threadID: String? = nil) -> Int {
    loadIfNeeded()
    return events.filter { event in
      event.kind == kind
        && (since.map { event.at >= $0 } ?? true)
        && (connectionID.map { event.connectionID == $0 } ?? true)
        && (threadID.map { event.threadID == $0 } ?? true)
    }.count
  }

  public func snapshot(queueDepth: Int) -> MetricsSnapshot {
    loadIfNeeded()
    let dayAgo = Date().addingTimeInterval(-24 * 3600)
    var counts: [String: Int] = [:]
    var last24h: [String: Int] = [:]
    var perConnection: [String: Int] = [:]
    var buckets = Array(repeating: 0, count: 24)
    var draftTokens: [Double] = []

    for event in events {
      counts[event.kind.rawValue, default: 0] += 1
      if event.at >= dayAgo {
        last24h[event.kind.rawValue, default: 0] += 1
        if event.kind == .sent {
          if let connectionID = event.connectionID { perConnection[connectionID, default: 0] += 1 }
          let hoursAgo = Int(Date().timeIntervalSince(event.at) / 3600)
          let index = 23 - min(23, max(0, hoursAgo))
          buckets[index] += 1
        }
      }
      if event.kind == .drafted, let tokens = event.value { draftTokens.append(tokens) }
    }

    return MetricsSnapshot(
      counts: counts,
      last24h: last24h,
      perConnectionSent24h: perConnection,
      sentByHour: buckets,
      tokensPerSecond: throughputSamples.isEmpty ? 0 : throughputSamples.reduce(0, +) / Double(throughputSamples.count),
      averageDraftTokens: draftTokens.isEmpty ? 0 : draftTokens.reduce(0, +) / Double(draftTokens.count),
      uptimeSeconds: Date().timeIntervalSince(startedAt),
      queueDepth: queueDepth,
      startedAt: startedAt
    )
  }

  private func prune() {
    let cutoff = Date().addingTimeInterval(-retention)
    if events.contains(where: { $0.at < cutoff }) {
      events.removeAll { $0.at < cutoff }
    }
  }
}
