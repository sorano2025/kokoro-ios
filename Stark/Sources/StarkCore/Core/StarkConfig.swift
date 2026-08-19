//
//  StarkCore
//
import Foundation

/// Everything the server needs to boot, persisted as JSON next to the rest of
/// the state so a relaunch picks up exactly where the previous run stopped.
public struct StarkConfig: Codable, Sendable, Equatable {
  /// TCP port the control server listens on.
  public var port: UInt16
  /// When `true` the listener only accepts loopback connections, so the server
  /// is reachable from Safari on the same phone but not from the network.
  public var loopbackOnly: Bool
  /// Bearer token required by every `/api` route. Generated on first launch.
  public var apiToken: String
  /// Identifier of the model the runtime should load at boot, if any.
  public var activeModelID: String?
  /// How replies leave the device.
  public var publishing: PublishingPolicy
  /// Persona the model writes as.
  public var persona: Persona
  /// Hard limits applied before anything is sent.
  public var limits: RateLimits
  /// How often the automation loop wakes up, in seconds.
  public var tickInterval: TimeInterval
  /// Sampling settings handed to the language model.
  public var sampling: SamplingOptions

  public init(
    port: UInt16 = 8137,
    loopbackOnly: Bool = true,
    apiToken: String = StarkConfig.freshToken(),
    activeModelID: String? = nil,
    publishing: PublishingPolicy = .init(),
    persona: Persona = .default,
    limits: RateLimits = .init(),
    tickInterval: TimeInterval = 120,
    sampling: SamplingOptions = .init()
  ) {
    self.port = port
    self.loopbackOnly = loopbackOnly
    self.apiToken = apiToken
    self.activeModelID = activeModelID
    self.publishing = publishing
    self.persona = persona
    self.limits = limits
    self.tickInterval = tickInterval
    self.sampling = sampling
  }

  /// 32 hex characters of `SystemRandomNumberGenerator` output.
  public static func freshToken() -> String {
    (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
  }
}

/// Controls whether drafts are posted automatically or held for a human.
public struct PublishingPolicy: Codable, Sendable, Equatable {
  /// Draft handling.
  public enum Mode: String, Codable, Sendable, CaseIterable {
    /// Every draft lands in the review queue and waits for an explicit approve.
    case review
    /// Drafts that clear every guardrail are sent without review. Everything
    /// the guardrails flag still falls back to the review queue.
    case autoWithinGuardrails
    /// Nothing is sent; drafts are written to the queue and marked as such.
    case dryRun
  }

  public var mode: Mode
  /// Appended to automated posts so recipients can tell a bot wrote them.
  /// Platform rules (and, in several jurisdictions, law) require this for
  /// automated accounts, so it defaults on.
  public var discloseAutomation: Bool
  /// The disclosure text itself. Kept short so it survives length limits.
  public var disclosureText: String
  /// Minimum seconds between two sends on the same connection. Spreads replies
  /// out instead of firing a burst the moment a batch is fetched.
  public var minSecondsBetweenSends: TimeInterval
  /// Random extra delay, in seconds, added on top of `minSecondsBetweenSends`.
  public var sendJitter: ClosedRange<TimeInterval> {
    get { jitterLow...max(jitterLow, jitterHigh) }
    set { jitterLow = newValue.lowerBound; jitterHigh = newValue.upperBound }
  }
  private var jitterLow: TimeInterval
  private var jitterHigh: TimeInterval

  public init(
    mode: Mode = .review,
    discloseAutomation: Bool = true,
    disclosureText: String = "(automated reply)",
    minSecondsBetweenSends: TimeInterval = 90,
    jitter: ClosedRange<TimeInterval> = 5...240
  ) {
    self.mode = mode
    self.discloseAutomation = discloseAutomation
    self.disclosureText = disclosureText
    self.minSecondsBetweenSends = minSecondsBetweenSends
    self.jitterLow = jitter.lowerBound
    self.jitterHigh = jitter.upperBound
  }
}

/// Ceilings enforced by `GuardRails` before a draft can be sent.
public struct RateLimits: Codable, Sendable, Equatable {
  public var repliesPerHourPerPlatform: Int
  public var repliesPerDayPerPlatform: Int
  public var repliesPerDayPerThread: Int
  public var maxLinksPerReply: Int
  /// Two drafts more similar than this (Jaccard over word trigrams) are treated
  /// as the same canned message and the second one is refused.
  public var maxSimilarityToRecent: Double
  /// How many recent replies the similarity check looks back over.
  public var similarityWindow: Int

  public init(
    repliesPerHourPerPlatform: Int = 6,
    repliesPerDayPerPlatform: Int = 40,
    repliesPerDayPerThread: Int = 1,
    maxLinksPerReply: Int = 1,
    maxSimilarityToRecent: Double = 0.55,
    similarityWindow: Int = 60
  ) {
    self.repliesPerHourPerPlatform = repliesPerHourPerPlatform
    self.repliesPerDayPerPlatform = repliesPerDayPerPlatform
    self.repliesPerDayPerThread = repliesPerDayPerThread
    self.maxLinksPerReply = maxLinksPerReply
    self.maxSimilarityToRecent = maxSimilarityToRecent
    self.similarityWindow = similarityWindow
  }
}

/// Decoding settings for the language model.
public struct SamplingOptions: Codable, Sendable, Equatable {
  public var temperature: Float
  public var topP: Float
  public var maxTokens: Int
  public var repetitionPenalty: Float

  public init(temperature: Float = 0.75, topP: Float = 0.92, maxTokens: Int = 320, repetitionPenalty: Float = 1.06) {
    self.temperature = temperature
    self.topP = topP
    self.maxTokens = maxTokens
    self.repetitionPenalty = repetitionPenalty
  }
}
