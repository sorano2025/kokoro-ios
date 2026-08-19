//
//  StarkCore
//
import Foundation

public enum PlatformKind: String, Codable, Sendable, CaseIterable {
  case mastodon
  case discord
  case telegram
  case webhook
  /// Any REST API described by a `GenericRESTConnector.Spec` in the config.
  case generic
}

/// Something addressed to the account: a mention, a DM, a comment.
public struct InboundItem: Codable, Sendable, Identifiable, Equatable {
  public let id: String
  public let connectionID: String
  public let platform: PlatformKind
  /// Thread/conversation this belongs to, used for the per-thread rate limit.
  public let threadID: String
  public let authorHandle: String
  public let text: String
  public let createdAt: Date
  /// Deep link back to the original, shown in the review queue.
  public let permalink: String?

  public init(
    id: String,
    connectionID: String,
    platform: PlatformKind,
    threadID: String,
    authorHandle: String,
    text: String,
    createdAt: Date,
    permalink: String? = nil
  ) {
    self.id = id
    self.connectionID = connectionID
    self.platform = platform
    self.threadID = threadID
    self.authorHandle = authorHandle
    self.text = text
    self.createdAt = createdAt
    self.permalink = permalink
  }

  /// What a connector needs in `OutboundPost.inReplyTo` to answer this item.
  ///
  /// Most platforms reply to the message id; Telegram's send endpoint is
  /// addressed by chat, so it needs the thread instead. Getting this wrong
  /// posts into the void, which is why it lives here rather than at each
  /// call site.
  public var replyTarget: String {
    switch platform {
    case .telegram: threadID
    default: id
    }
  }
}

/// Text on its way out.
public struct OutboundPost: Codable, Sendable, Equatable {
  public var text: String
  /// Set when this is a reply rather than a standalone post.
  public var inReplyTo: String?
  /// Optional audio rendered by the on-device Kokoro TTS, for platforms that
  /// take voice notes.
  public var audioPath: String?

  public init(text: String, inReplyTo: String? = nil, audioPath: String? = nil) {
    self.text = text
    self.inReplyTo = inReplyTo
    self.audioPath = audioPath
  }
}

public struct PostReceipt: Codable, Sendable, Equatable {
  public let remoteID: String
  public let permalink: String?
  public let at: Date

  public init(remoteID: String, permalink: String? = nil, at: Date = Date()) {
    self.remoteID = remoteID
    self.permalink = permalink
    self.at = at
  }
}

public struct ConnectionHealth: Codable, Sendable, Equatable {
  public enum State: String, Codable, Sendable { case ok, degraded, unauthorized, offline }
  public var state: State
  public var accountHandle: String?
  public var detail: String?
  public var checkedAt: Date

  public init(state: State, accountHandle: String? = nil, detail: String? = nil, checkedAt: Date = Date()) {
    self.state = state
    self.accountHandle = accountHandle
    self.detail = detail
    self.checkedAt = checkedAt
  }
}

/// Sendable error carried back across actor boundaries.
///
/// `any Error` is an existential the compiler cannot prove is safe to hand
/// between isolation domains, so results that cross one carry this instead of
/// whatever URLSession threw.
public struct SendFailure: Error, LocalizedError, Sendable, Equatable {
  public let message: String
  public init(_ message: String) { self.message = message }
  public init(_ error: any Error) { self.message = error.localizedDescription }
  public var errorDescription: String? { message }
}

public enum ConnectorError: Error, LocalizedError {
  case notConfigured(String)
  case http(status: Int, body: String)
  case decoding(String)
  case unsupported(String)

  public var errorDescription: String? {
    switch self {
    case .notConfigured(let what): "Not configured: \(what)"
    case .http(let status, let body): "HTTP \(status): \(body.prefix(200))"
    case .decoding(let what): "Could not decode \(what)"
    case .unsupported(let what): "\(what) is not supported by this connector"
    }
  }
}

/// One account on one platform.
///
/// Connectors talk to documented public APIs with a token the user pastes in.
/// Nothing here scrapes a site or drives a logged-in web session, because both
/// break the terms of every platform worth connecting to.
public protocol PlatformConnector: Sendable {
  var connectionID: String { get }
  var kind: PlatformKind { get }
  var displayName: String { get }

  /// Confirms the credential works and reports which account it belongs to.
  func verify() async throws -> ConnectionHealth
  /// Items addressed to the account since `since`, newest last.
  func fetchInbox(since: Date?) async throws -> [InboundItem]
  /// Sends a reply or a standalone post.
  func send(_ post: OutboundPost) async throws -> PostReceipt
}

public extension PlatformConnector {
  var displayName: String { kind.rawValue }
}
