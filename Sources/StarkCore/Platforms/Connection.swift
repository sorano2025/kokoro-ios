//
//  StarkCore
//
import Foundation

/// The persisted half of a connection. The secret lives in the keychain under
/// the same `id`, so this struct is safe to hand to the dashboard.
public struct Connection: Codable, Sendable, Identifiable, Equatable {
  public var id: String
  public var kind: PlatformKind
  public var label: String
  /// Instance host for Mastodon, channel id for Discord, target URL for a
  /// webhook — whatever the connector needs beyond the token.
  public var endpoint: String
  /// Extra per-connector settings, e.g. Mastodon visibility.
  public var options: [String: String]
  public var enabled: Bool
  /// Watermark so each poll only picks up items newer than the last pass.
  public var lastPolledAt: Date?
  public var lastSeenItemID: String?
  public var health: ConnectionHealth?

  public init(
    id: String = UUID().uuidString.lowercased(),
    kind: PlatformKind,
    label: String,
    endpoint: String,
    options: [String: String] = [:],
    enabled: Bool = true
  ) {
    self.id = id
    self.kind = kind
    self.label = label
    self.endpoint = endpoint
    self.options = options
    self.enabled = enabled
  }

  public var hasCredential: Bool { TokenStore.get(id) != nil }
}
