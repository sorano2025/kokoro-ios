//
//  StarkCore
//
import Foundation

/// A connector described by JSON instead of by Swift.
///
/// New platforms show up faster than a shipped binary can follow, so any REST
/// API that returns a JSON array of messages and accepts a JSON post can be
/// wired up from the dashboard by filling in a spec — no rebuild, no App Store
/// round trip.
public struct GenericRESTConnector: PlatformConnector {
  /// Field-by-field description of somebody else's API.
  public struct Spec: Codable, Sendable, Equatable {
    public var inboxURL: String?
    public var inboxMethod: String = "GET"
    /// Dot path to the array of items, e.g. "data.messages". Empty = root.
    public var itemsPath: String = ""
    public var idField: String = "id"
    public var textField: String = "text"
    public var authorField: String = "author"
    public var threadField: String?
    public var dateField: String?
    /// "iso8601" or "epoch".
    public var dateFormat: String = "iso8601"
    public var permalinkField: String?
    public var sendURL: String?
    public var sendMethod: String = "POST"
    /// JSON body template. `{{text}}` and `{{reply_to}}` are substituted, with
    /// JSON string escaping applied to the values.
    public var sendTemplate: String = "{\"text\":\"{{text}}\"}"
    /// Header name carrying the keychain token, e.g. "Authorization".
    public var authHeaderName: String = "Authorization"
    /// Template for the header value; `{{token}}` is substituted.
    public var authHeaderTemplate: String = "Bearer {{token}}"
    public var extraHeaders: [String: String] = [:]
    public var query: [String: String] = [:]

    public init() {}
  }

  public let connectionID: String
  public let kind: PlatformKind = .generic
  public let displayName: String
  let spec: Spec
  private let client = HTTPClient()

  public init(connection: Connection) throws {
    self.connectionID = connection.id
    self.displayName = connection.label
    guard let raw = connection.options["spec"], let data = raw.data(using: .utf8) else {
      throw ConnectorError.notConfigured("spec for \(connection.label)")
    }
    self.spec = try JSONDecoder.stark.decode(Spec.self, from: data)
  }

  private func headers() -> [String: String] {
    var headers = spec.extraHeaders
    if let token = TokenStore.get(connectionID) {
      headers[spec.authHeaderName] = spec.authHeaderTemplate.replacingOccurrences(of: "{{token}}", with: token)
    }
    return headers
  }

  public func verify() async throws -> ConnectionHealth {
    guard let inbox = spec.inboxURL ?? spec.sendURL, let url = URL(string: inbox) else {
      return ConnectionHealth(state: .unauthorized, detail: "spec has no usable URL")
    }
    do {
      _ = try await client.request(spec.inboxURL == nil ? "HEAD" : spec.inboxMethod, url, headers: headers(), query: spec.query)
      return ConnectionHealth(state: .ok, accountHandle: url.host)
    } catch let ConnectorError.http(status, body) {
      return ConnectionHealth(state: status == 401 || status == 403 ? .unauthorized : .degraded, detail: String(body.prefix(140)))
    } catch {
      return ConnectionHealth(state: .offline, detail: error.localizedDescription)
    }
  }

  public func fetchInbox(since: Date?) async throws -> [InboundItem] {
    guard let inbox = spec.inboxURL, let url = URL(string: inbox) else { return [] }
    let data = try await client.request(spec.inboxMethod, url, headers: headers(), query: spec.query)
    let root = try JSONSerialization.jsonObject(with: data)
    let container = spec.itemsPath.isEmpty ? root : JSONPath.value(at: spec.itemsPath, in: root)
    guard let items = container as? [Any] else {
      throw ConnectorError.decoding("array at '\(spec.itemsPath)'")
    }
    return items.compactMap { item in
      guard let text = JSONPath.string(at: spec.textField, in: item), !text.isEmpty else { return nil }
      let id = JSONPath.string(at: spec.idField, in: item) ?? UUID().uuidString
      let created = spec.dateField.flatMap { JSONPath.date(at: $0, in: item, format: spec.dateFormat) } ?? Date()
      if let since, created < since { return nil }
      return InboundItem(
        id: id,
        connectionID: connectionID,
        platform: .generic,
        threadID: spec.threadField.flatMap { JSONPath.string(at: $0, in: item) } ?? id,
        authorHandle: JSONPath.string(at: spec.authorField, in: item) ?? "unknown",
        text: text,
        createdAt: created,
        permalink: spec.permalinkField.flatMap { JSONPath.string(at: $0, in: item) }
      )
    }
  }

  public func send(_ post: OutboundPost) async throws -> PostReceipt {
    guard let send = spec.sendURL, let url = URL(string: send) else {
      throw ConnectorError.notConfigured("sendURL")
    }
    let body = spec.sendTemplate
      .replacingOccurrences(of: "{{text}}", with: JSONPath.escape(post.text))
      .replacingOccurrences(of: "{{reply_to}}", with: JSONPath.escape(post.inReplyTo ?? ""))
    var request = URLRequest(url: url)
    request.httpMethod = spec.sendMethod
    request.httpBody = Data(body.utf8)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (key, value) in headers() { request.setValue(value, forHTTPHeaderField: key) }
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
      throw ConnectorError.http(status: status, body: String(decoding: data, as: UTF8.self))
    }
    let remoteID = JSONPath.string(at: spec.idField, in: try? JSONSerialization.jsonObject(with: data)) ?? UUID().uuidString
    return PostReceipt(remoteID: remoteID)
  }
}

/// Dotted-key lookups into `JSONSerialization` output, with numeric segments
/// indexing arrays: "data.items.0.author.name".
enum JSONPath {
  static func value(at path: String, in object: Any?) -> Any? {
    var current = object
    for segment in path.split(separator: ".") {
      if let index = Int(segment), let array = current as? [Any], array.indices.contains(index) {
        current = array[index]
      } else if let dictionary = current as? [String: Any] {
        current = dictionary[String(segment)]
      } else {
        return nil
      }
    }
    return current
  }

  static func string(at path: String, in object: Any?) -> String? {
    switch value(at: path, in: object) {
    case let text as String: text
    case let number as NSNumber: number.stringValue
    default: nil
    }
  }

  static func date(at path: String, in object: Any?, format: String) -> Date? {
    switch value(at: path, in: object) {
    case let seconds as NSNumber where format == "epoch":
      Date(timeIntervalSince1970: seconds.doubleValue)
    case let text as String:
      Date.starkParse(text)
    default:
      nil
    }
  }

  /// Escapes a value for interpolation into a JSON string literal.
  static func escape(_ value: String) -> String {
    var escaped = ""
    for character in value.unicodeScalars {
      switch character {
      case "\"": escaped += "\\\""
      case "\\": escaped += "\\\\"
      case "\n": escaped += "\\n"
      case "\r": escaped += "\\r"
      case "\t": escaped += "\\t"
      case let scalar where scalar.value < 0x20: escaped += String(format: "\\u%04x", scalar.value)
      case let scalar: escaped.unicodeScalars.append(scalar)
      }
    }
    return escaped
  }
}
