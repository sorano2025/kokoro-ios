//
//  StarkCore
//
import Foundation

public extension Date {
  /// Parses the timestamp shapes the connected APIs actually emit.
  ///
  /// Mastodon sends fractional seconds, Discord sends six-digit microseconds
  /// with an offset, some hosts drop the seconds entirely, and `.iso8601`
  /// alone rejects two of the three.
  static func starkParse(_ text: String) -> Date? {
    if let date = fractionalISO.date(from: text) { return date }
    if let date = plainISO.date(from: text) { return date }
    if let seconds = TimeInterval(text) { return Date(timeIntervalSince1970: seconds) }
    return nil
  }

  private static let fractionalISO: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static let plainISO: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()
}
