//
//  StarkCore
//
import Foundation

/// Telegram Bot API. `endpoint` is unused; the token identifies the bot.
///
/// `getUpdates` is a consuming read: acknowledging an update id drops it from
/// Telegram's queue forever, so the offset watermark is persisted on the
/// `Connection` rather than held in memory where a crash would lose messages.
public struct TelegramConnector: PlatformConnector {
  public let connectionID: String
  public let kind: PlatformKind = .telegram
  public let displayName: String
  let offset: Int?
  private let client = HTTPClient()

  public init(connection: Connection) {
    self.connectionID = connection.id
    self.displayName = connection.label
    self.offset = connection.lastSeenItemID.flatMap(Int.init)
  }

  private func url(_ method: String) throws -> URL {
    guard let token = TokenStore.get(connectionID) else {
      throw ConnectorError.notConfigured("bot token for \(displayName)")
    }
    guard let url = URL(string: "https://api.telegram.org/bot\(token)/\(method)") else {
      throw ConnectorError.notConfigured("telegram endpoint")
    }
    return url
  }

  public func verify() async throws -> ConnectionHealth {
    do {
      let data = try await client.request("GET", try url("getMe"))
      let response = try client.decode(Response<Me>.self, from: data, what: "getMe")
      return ConnectionHealth(state: .ok, accountHandle: "@\(response.result.username ?? response.result.first_name)")
    } catch let ConnectorError.http(status, body) where status == 401 {
      return ConnectionHealth(state: .unauthorized, detail: String(body.prefix(140)))
    } catch {
      return ConnectionHealth(state: .offline, detail: error.localizedDescription)
    }
  }

  public func fetchInbox(since: Date?) async throws -> [InboundItem] {
    var query = ["limit": "20", "timeout": "0"]
    if let offset { query["offset"] = String(offset + 1) }
    let data = try await client.request("GET", try url("getUpdates"), query: query)
    let response = try client.decode(Response<[Update]>.self, from: data, what: "updates")
    return response.result.compactMap { update in
      guard let message = update.message, let text = message.text else { return nil }
      let handle = message.from?.username.map { "@\($0)" } ?? message.from?.first_name ?? "unknown"
      return InboundItem(
        id: String(update.update_id),
        connectionID: connectionID,
        platform: .telegram,
        threadID: String(message.chat.id),
        authorHandle: handle,
        text: text,
        createdAt: Date(timeIntervalSince1970: TimeInterval(message.date))
      )
    }
  }

  public func send(_ post: OutboundPost) async throws -> PostReceipt {
    struct Body: Encodable, Sendable {
      let chat_id: String
      let text: String
      let reply_to_message_id: Int?
    }
    guard let chatID = post.inReplyTo else {
      throw ConnectorError.unsupported("Telegram sends need a chat id in inReplyTo")
    }
    let data = try await client.request("POST", try url("sendMessage"), json: Body(chat_id: chatID, text: post.text, reply_to_message_id: nil))
    let response = try client.decode(Response<Message>.self, from: data, what: "sendMessage")
    return PostReceipt(remoteID: String(response.result.message_id ?? 0))
  }

  private struct Response<T: Decodable>: Decodable { let ok: Bool; let result: T }
  private struct Me: Decodable { let username: String?; let first_name: String }
  private struct User: Decodable { let username: String?; let first_name: String? }
  private struct Chat: Decodable { let id: Int }
  private struct Message: Decodable {
    let message_id: Int?
    let text: String?
    let date: Int
    let chat: Chat
    let from: User?
  }
  private struct Update: Decodable { let update_id: Int; let message: Message? }
}
