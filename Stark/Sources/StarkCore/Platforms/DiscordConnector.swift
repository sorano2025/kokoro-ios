//
//  StarkCore
//
import Foundation

/// Discord bot posting into one channel. `endpoint` is the channel id.
///
/// REST polling rather than the gateway websocket: the phone sleeps, and a
/// socket that dies every time the app is suspended is worse than a poll that
/// simply resumes with an `after` cursor.
public struct DiscordConnector: PlatformConnector {
  public let connectionID: String
  public let kind: PlatformKind = .discord
  public let displayName: String
  let channelID: String
  let afterID: String?
  private let client = HTTPClient()
  private static let base = "https://discord.com/api/v10"

  public init(connection: Connection) {
    self.connectionID = connection.id
    self.displayName = connection.label
    self.channelID = connection.endpoint
    self.afterID = connection.lastSeenItemID
  }

  private func authHeaders() throws -> [String: String] {
    guard let token = TokenStore.get(connectionID) else {
      throw ConnectorError.notConfigured("bot token for \(displayName)")
    }
    return ["Authorization": "Bot \(token)", "User-Agent": "StarkServer (ios, 1.0)"]
  }

  private func url(_ path: String) throws -> URL {
    guard let url = URL(string: Self.base + path) else { throw ConnectorError.notConfigured("discord url") }
    return url
  }

  public func verify() async throws -> ConnectionHealth {
    do {
      let data = try await client.request("GET", try url("/users/@me"), headers: try authHeaders())
      let me = try client.decode(User.self, from: data, what: "user")
      _ = try await client.request("GET", try url("/channels/\(channelID)"), headers: try authHeaders())
      return ConnectionHealth(state: .ok, accountHandle: me.username)
    } catch let ConnectorError.http(status, body) where status == 401 || status == 403 {
      return ConnectionHealth(state: .unauthorized, detail: String(body.prefix(140)))
    } catch {
      return ConnectionHealth(state: .offline, detail: error.localizedDescription)
    }
  }

  public func fetchInbox(since: Date?) async throws -> [InboundItem] {
    var query = ["limit": "20"]
    if let afterID { query["after"] = afterID }
    let data = try await client.request("GET", try url("/channels/\(channelID)/messages"), headers: try authHeaders(), query: query)
    let messages = try client.decode([Message].self, from: data, what: "messages")
    // Discord returns newest first; the pipeline reads a batch oldest to
    // newest so a thread's context arrives in the order it was written.
    return Array(messages
      .filter { $0.author.bot != true && !($0.content ?? "").isEmpty }
      .map { message in
        InboundItem(
          id: message.id,
          connectionID: connectionID,
          platform: .discord,
          threadID: channelID,
          authorHandle: "@\(message.author.username)",
          text: message.content ?? "",
          createdAt: message.timestamp,
          permalink: "https://discord.com/channels/@me/\(channelID)/\(message.id)"
        )
      }
      .reversed())
  }

  public func send(_ post: OutboundPost) async throws -> PostReceipt {
    struct Reference: Encodable, Sendable { let message_id: String }
    struct Body: Encodable, Sendable { let content: String; let message_reference: Reference? }
    let body = Body(content: post.text, message_reference: post.inReplyTo.map(Reference.init))
    let data = try await client.request("POST", try url("/channels/\(channelID)/messages"), headers: try authHeaders(), json: body)
    let message = try client.decode(Message.self, from: data, what: "message")
    return PostReceipt(remoteID: message.id)
  }

  private struct User: Decodable { let username: String; let bot: Bool? }
  private struct Message: Decodable {
    let id: String
    let content: String?
    let timestamp: Date
    let author: User
  }
}
