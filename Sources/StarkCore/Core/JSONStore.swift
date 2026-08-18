//
//  StarkCore
//
import Foundation

/// A tiny atomic JSON file store.
///
/// The volumes involved are small — queue entries, metric buckets, connection
/// descriptors — so a whole-file rewrite per mutation is cheaper than carrying
/// a database dependency, and an atomic write keeps the file readable if the
/// app is jetsammed mid-save.
public actor JSONStore<Value: Codable & Sendable> {
  private let url: URL
  private let fallback: @Sendable () -> Value
  private var cached: Value?

  public init(filename: String, fallback: @escaping @Sendable () -> Value) {
    self.url = StarkPaths.file(filename)
    self.fallback = fallback
  }

  public func load() -> Value {
    if let cached { return cached }
    guard let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder.stark.decode(Value.self, from: data)
    else {
      let value = fallback()
      cached = value
      return value
    }
    cached = decoded
    return decoded
  }

  public func save(_ value: Value) {
    cached = value
    guard let data = try? JSONEncoder.stark.encode(value) else { return }
    try? data.write(to: url, options: .atomic)
  }

  /// Read-modify-write under the actor's isolation.
  @discardableResult
  public func mutate<T: Sendable>(_ body: @Sendable (inout Value) -> T) -> T {
    var value = load()
    let result = body(&value)
    save(value)
    return result
  }
}

extension JSONEncoder {
  public static var stark: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.withoutEscapingSlashes]
    return encoder
  }
}

extension JSONDecoder {
  public static var stark: JSONDecoder {
    let decoder = JSONDecoder()
    // Lenient on purpose: the same decoder reads our own files and third-party
    // API payloads, and those disagree about fractional seconds.
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      if let text = try? container.decode(String.self), let date = Date.starkParse(text) {
        return date
      }
      if let seconds = try? container.decode(Double.self) {
        return Date(timeIntervalSince1970: seconds)
      }
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "unrecognised date")
    }
    return decoder
  }
}
