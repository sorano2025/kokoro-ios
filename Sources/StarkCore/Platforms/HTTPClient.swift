//
//  StarkCore
//
import Foundation

/// Thin JSON helper shared by the connectors.
struct HTTPClient: Sendable {
  var session: URLSession = .shared

  func request(
    _ method: String,
    _ url: URL,
    headers: [String: String] = [:],
    query: [String: String] = [:],
    json: (any Encodable & Sendable)? = nil,
    form: [String: String]? = nil
  ) async throws -> Data {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    if !query.isEmpty {
      components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
    }
    guard let finalURL = components?.url else { throw ConnectorError.notConfigured("url") }

    var request = URLRequest(url: finalURL)
    request.httpMethod = method
    request.timeoutInterval = 30
    for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }

    if let json {
      request.httpBody = try JSONEncoder.stark.encode(AnyEncodable(json))
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    } else if let form {
      let body = form.map { "\(Self.escape($0.key))=\(Self.escape($0.value))" }.joined(separator: "&")
      request.httpBody = Data(body.utf8)
      request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    }

    let (data, response) = try await session.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
      throw ConnectorError.http(status: status, body: String(decoding: data, as: UTF8.self))
    }
    return data
  }

  func decode<T: Decodable>(_ type: T.Type, from data: Data, what: String) throws -> T {
    do {
      return try JSONDecoder.stark.decode(type, from: data)
    } catch {
      throw ConnectorError.decoding("\(what): \(error)")
    }
  }

  private static func escape(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
  }
}

/// Lets the client take a heterogeneous body without generics leaking upward.
struct AnyEncodable: Encodable {
  private let encodeBody: @Sendable (Encoder) throws -> Void
  init(_ wrapped: any Encodable & Sendable) {
    encodeBody = { encoder in try wrapped.encode(to: encoder) }
  }
  func encode(to encoder: Encoder) throws { try encodeBody(encoder) }
}
