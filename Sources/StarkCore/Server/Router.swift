//
//  StarkCore
//
import Foundation

/// Minimal path router: exact segments plus `:name` captures.
public struct Router: Sendable {
  public struct Route: Sendable {
    let method: String
    let segments: [String]
    let handler: @Sendable (HTTPRequest, [String: String]) async -> HTTPResponse
  }

  private var routes: [Route] = []

  public init() {}

  public mutating func add(_ method: String, _ path: String, _ handler: @escaping @Sendable (HTTPRequest, [String: String]) async -> HTTPResponse) {
    routes.append(Route(method: method, segments: Self.split(path), handler: handler))
  }

  public func handle(_ request: HTTPRequest) async -> HTTPResponse {
    let requested = Self.split(request.path)
    var methodMismatch = false
    for route in routes {
      guard route.segments.count == requested.count else { continue }
      var parameters: [String: String] = [:]
      var matches = true
      for (pattern, value) in zip(route.segments, requested) {
        if pattern.hasPrefix(":") {
          parameters[String(pattern.dropFirst())] = value
        } else if pattern != value {
          matches = false
          break
        }
      }
      guard matches else { continue }
      guard route.method == request.method else {
        methodMismatch = true
        continue
      }
      return await route.handler(request, parameters)
    }
    return methodMismatch ? .error(405, "method not allowed") : .error(404, "no route for \(request.path)")
  }

  private static func split(_ path: String) -> [String] {
    path.split(separator: "/").map(String.init)
  }
}
