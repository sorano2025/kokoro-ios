//
//  StarkCore
//
import Foundation

public struct HTTPRequest: Sendable {
  public var method: String
  public var path: String
  public var query: [String: String]
  public var headers: [String: String]
  public var body: Data

  public init(method: String, path: String, query: [String: String] = [:], headers: [String: String] = [:], body: Data = Data()) {
    self.method = method
    self.path = path
    self.query = query
    self.headers = headers
    self.body = body
  }

  public func header(_ name: String) -> String? { headers[name.lowercased()] }

  public func decode<T: Decodable>(_ type: T.Type) throws -> T {
    try JSONDecoder.stark.decode(type, from: body)
  }

  /// Parses the request line, headers and body out of a raw buffer.
  /// Returns `nil` while the message is still incomplete.
  static func parse(_ buffer: Data) -> (request: HTTPRequest, consumed: Int)? {
    guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
    let headerData = buffer[buffer.startIndex..<headerEnd.lowerBound]
    guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
    var lines = headerText.components(separatedBy: "\r\n")
    guard !lines.isEmpty else { return nil }

    let requestLine = lines.removeFirst().split(separator: " ")
    guard requestLine.count >= 2 else { return nil }
    let method = String(requestLine[0])
    let target = String(requestLine[1])

    var headers: [String: String] = [:]
    for line in lines {
      guard let colon = line.firstIndex(of: ":") else { continue }
      let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
      let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
      headers[name] = value
    }

    let contentLength = Int(headers["content-length"] ?? "0") ?? 0
    let bodyStart = headerEnd.upperBound
    let available = buffer.distance(from: bodyStart, to: buffer.endIndex)
    guard available >= contentLength else { return nil }
    let body = Data(buffer[bodyStart..<buffer.index(bodyStart, offsetBy: contentLength)])

    var path = target
    var query: [String: String] = [:]
    if let mark = target.firstIndex(of: "?") {
      path = String(target[target.startIndex..<mark])
      let queryString = String(target[target.index(after: mark)...])
      for pair in queryString.split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1)
        let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
        let value = parts.count > 1 ? (String(parts[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? "") : ""
        query[key] = value
      }
    }

    let consumed = buffer.distance(from: buffer.startIndex, to: bodyStart) + contentLength
    return (HTTPRequest(method: method, path: path, query: query, headers: headers, body: body), consumed)
  }
}

public struct HTTPResponse: Sendable {
  public enum Body: Sendable {
    case data(Data)
    /// Server-sent events. Each string is one already-formatted `data:` frame.
    case stream(AsyncStream<String>)
  }

  public var status: Int
  public var headers: [String: String]
  public var body: Body

  public init(status: Int = 200, headers: [String: String] = [:], body: Body = .data(Data())) {
    self.status = status
    self.headers = headers
    self.body = body
  }

  public static func json(_ value: some Encodable & Sendable, status: Int = 200) -> HTTPResponse {
    let data = (try? JSONEncoder.stark.encode(AnyEncodable(value))) ?? Data("{}".utf8)
    return HTTPResponse(status: status, headers: ["Content-Type": "application/json; charset=utf-8"], body: .data(data))
  }

  public static func text(_ value: String, status: Int = 200) -> HTTPResponse {
    HTTPResponse(status: status, headers: ["Content-Type": "text/plain; charset=utf-8"], body: .data(Data(value.utf8)))
  }

  public static func html(_ value: String, status: Int = 200) -> HTTPResponse {
    HTTPResponse(status: status, headers: ["Content-Type": "text/html; charset=utf-8"], body: .data(Data(value.utf8)))
  }

  public static func error(_ status: Int, _ message: String) -> HTTPResponse {
    struct Payload: Encodable, Sendable { let error: String }
    return .json(Payload(error: message), status: status)
  }

  public static func events(_ stream: AsyncStream<String>) -> HTTPResponse {
    HTTPResponse(
      status: 200,
      headers: [
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        "Connection": "keep-alive",
      ],
      body: .stream(stream)
    )
  }

  static let reasons: [Int: String] = [
    200: "OK", 201: "Created", 204: "No Content", 400: "Bad Request", 401: "Unauthorized",
    403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 409: "Conflict",
    422: "Unprocessable Entity", 500: "Internal Server Error", 503: "Service Unavailable",
  ]

  /// Status line plus headers. The body is written separately so streams can
  /// keep the connection open.
  func headerData() -> Data {
    var text = "HTTP/1.1 \(status) \(Self.reasons[status] ?? "OK")\r\n"
    var headers = headers
    headers["Server"] = "stark/1.0"
    // The dashboard is same-origin, so no CORS allowance is handed out here.
    headers["X-Content-Type-Options"] = "nosniff"
    if case .data(let data) = body {
      headers["Content-Length"] = String(data.count)
      headers["Connection"] = "close"
    }
    for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
      text += "\(name): \(value)\r\n"
    }
    text += "\r\n"
    return Data(text.utf8)
  }
}
