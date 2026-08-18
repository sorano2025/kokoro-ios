//
//  StarkCore
//
import Foundation

/// Mastodon / Pleroma / GoToSocial — anything speaking the Mastodon REST API.
///
/// The pick of the bunch for this kind of automation: an access token is a
/// two-minute copy-paste from the account's own settings, mentions arrive over
/// a documented endpoint, and bot accounts are explicitly allowed as long as
/// they set the bot flag.
public struct MastodonConnector: PlatformConnector {
  public let connectionID: String
  public let kind: PlatformKind = .mastodon
  public let displayName: String
  /// Instance host, e.g. "mastodon.social".
  let host: String
  let visibility: String
  let sinceID: String?
  private let client = HTTPClient()

  public init(connection: Connection) {
    self.connectionID = connection.id
    self.displayName = connection.label
    self.host = connection.endpoint.replacingOccurrences(of: "https://", with: "")
    self.visibility = connection.options["visibility"] ?? "public"
    self.sinceID = connection.lastSeenItemID
  }

  private func url(_ path: String) throws -> URL {
    guard let url = URL(string: "https://\(host)\(path)") else {
      throw ConnectorError.notConfigured("instance host '\(host)'")
    }
    return url
  }

  private func authHeaders() throws -> [String: String] {
    guard let token = TokenStore.get(connectionID) else {
      throw ConnectorError.notConfigured("access token for \(displayName)")
    }
    return ["Authorization": "Bearer \(token)"]
  }

  public func verify() async throws -> ConnectionHealth {
    do {
      let data = try await client.request("GET", try url("/api/v1/accounts/verify_credentials"), headers: try authHeaders())
      let account = try client.decode(Account.self, from: data, what: "account")
      return ConnectionHealth(state: .ok, accountHandle: "@\(account.acct)@\(host)", detail: account.bot == true ? "bot flag set" : "bot flag not set — set it in profile settings")
    } catch let ConnectorError.http(status, body) where status == 401 || status == 403 {
      return ConnectionHealth(state: .unauthorized, detail: String(body.prefix(140)))
    } catch {
      return ConnectionHealth(state: .offline, detail: error.localizedDescription)
    }
  }

  public func fetchInbox(since: Date?) async throws -> [InboundItem] {
    var query = ["limit": "20", "types[]": "mention"]
    if let sinceID { query["since_id"] = sinceID }
    let data = try await client.request("GET", try url("/api/v1/notifications"), headers: try authHeaders(), query: query)
    let notifications = try client.decode([MentionNotification].self, from: data, what: "notifications")
    return notifications.compactMap { notification in
      guard let status = notification.status else { return nil }
      return InboundItem(
        id: status.id,
        connectionID: connectionID,
        platform: .mastodon,
        threadID: status.in_reply_to_id ?? status.id,
        authorHandle: "@\(status.account.acct)",
        text: Self.plainText(fromHTML: status.content),
        createdAt: status.created_at,
        permalink: status.url
      )
    }
  }

  public func send(_ post: OutboundPost) async throws -> PostReceipt {
    struct Body: Encodable, Sendable {
      let status: String
      let in_reply_to_id: String?
      let visibility: String
    }
    let data = try await client.request(
      "POST",
      try url("/api/v1/statuses"),
      headers: try authHeaders(),
      json: Body(status: post.text, in_reply_to_id: post.inReplyTo, visibility: visibility)
    )
    let status = try client.decode(Status.self, from: data, what: "status")
    return PostReceipt(remoteID: status.id, permalink: status.url)
  }

  /// Statuses arrive as HTML fragments; the model only wants the words.
  static func plainText(fromHTML html: String) -> String {
    var text = html
    for (pattern, replacement) in [("<br\\s*/?>", "\n"), ("</p>", "\n\n"), ("<[^>]+>", "")] {
      text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }
    let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " "]
    for (entity, character) in entities { text = text.replacingOccurrences(of: entity, with: character) }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private struct Account: Decodable { let id: String; let acct: String; let bot: Bool? }
  private struct Status: Decodable {
    let id: String
    let content: String
    let created_at: Date
    let url: String?
    let in_reply_to_id: String?
    let account: Account
  }
  private struct MentionNotification: Decodable { let id: String; let type: String; let status: Status? }
}
