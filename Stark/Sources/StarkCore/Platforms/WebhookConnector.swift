//
//  StarkCore
//
import Foundation

/// Outbound-only sink: posts the finished text as JSON to any URL.
///
/// This is the escape hatch for platforms with no usable API — point it at a
/// Zapier/n8n/Make hook, a Slack incoming webhook, or a server you own, and
/// let that side do the last mile.
public struct WebhookConnector: PlatformConnector {
  public let connectionID: String
  public let kind: PlatformKind = .webhook
  public let displayName: String
  let target: String
  private let client = HTTPClient()

  public init(connection: Connection) {
    self.connectionID = connection.id
    self.displayName = connection.label
    self.target = connection.endpoint
  }

  private func headers() -> [String: String] {
    guard let secret = TokenStore.get(connectionID) else { return [:] }
    return ["Authorization": "Bearer \(secret)"]
  }

  public func verify() async throws -> ConnectionHealth {
    guard URL(string: target) != nil else {
      return ConnectionHealth(state: .unauthorized, detail: "'\(target)' is not a URL")
    }
    return ConnectionHealth(state: .ok, accountHandle: target, detail: "outbound only")
  }

  public func fetchInbox(since: Date?) async throws -> [InboundItem] { [] }

  public func send(_ post: OutboundPost) async throws -> PostReceipt {
    struct Body: Encodable, Sendable { let text: String; let in_reply_to: String?; let source: String }
    guard let url = URL(string: target) else { throw ConnectorError.notConfigured("webhook url") }
    _ = try await client.request("POST", url, headers: headers(), json: Body(text: post.text, in_reply_to: post.inReplyTo, source: "stark"))
    return PostReceipt(remoteID: UUID().uuidString)
  }
}
