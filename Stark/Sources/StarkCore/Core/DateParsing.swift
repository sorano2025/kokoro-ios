//
//  StarkCore
//
import Foundation

public extension Date {
  /// Parses the timestamp shapes the connected APIs actually emit.
  ///
  /// Mastodon sends fractional seconds, Discord sends microseconds with a
  /// colon-separated offset, some hosts send neither — and one strategy
  /// rejects two of the three. `Date.ISO8601FormatStyle` is used rather than
  /// `ISO8601DateFormatter` because the format styles are value types and
  /// `Sendable`, so they can live in a static without a data race.
  static func starkParse(_ text: String) -> Date? {
    for style in isoStyles {
      if let date = try? style.parse(text) { return date }
    }
    if let seconds = TimeInterval(text) { return Date(timeIntervalSince1970: seconds) }
    return nil
  }

  /// Ordered most-specific first: fractional seconds before whole seconds, and
  /// both offset spellings ("+0000" and "+00:00").
  private static let isoStyles: [Date.ISO8601FormatStyle] = [
    .init(includingFractionalSeconds: true),
    .init(timeZoneSeparator: .colon, includingFractionalSeconds: true),
    .init(),
    .init(timeZoneSeparator: .colon),
  ]
}
