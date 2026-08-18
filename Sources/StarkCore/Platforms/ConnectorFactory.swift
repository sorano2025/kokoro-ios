//
//  StarkCore
//
import Foundation

/// Builds a live connector from its persisted description.
public enum ConnectorFactory {
  public static func make(_ connection: Connection) throws -> any PlatformConnector {
    switch connection.kind {
    case .mastodon: MastodonConnector(connection: connection)
    case .telegram: TelegramConnector(connection: connection)
    case .discord: DiscordConnector(connection: connection)
    case .webhook: WebhookConnector(connection: connection)
    case .generic: try GenericRESTConnector(connection: connection)
    }
  }

  /// What the dashboard shows when adding a connection of each kind.
  public static func setupHint(for kind: PlatformKind) -> (endpointLabel: String, tokenLabel: String, help: String) {
    switch kind {
    case .mastodon:
      ("instance host", "access token",
       "Settings → Development → New application, scopes read:notifications write:statuses. Endpoint is the bare host, e.g. mastodon.social.")
    case .telegram:
      ("unused", "bot token",
       "Create the bot with @BotFather and paste the token. Replies go to the chat the message came from.")
    case .discord:
      ("channel id", "bot token",
       "Discord developer portal → Bot → token. Invite the bot with Read Messages and Send Messages, then paste the channel id.")
    case .webhook:
      ("target URL", "shared secret (optional)",
       "Posts {text, in_reply_to, source} as JSON. Use for platforms without an open API, via your own relay.")
    case .generic:
      ("label", "token (optional)",
       "Describe the API in the spec field: inbox URL, item paths and a send template. No rebuild needed.")
    }
  }
}
