//
//  StarkUI
//
#if canImport(SwiftUI)
import SwiftUI
import StarkCore

/// Two ink levels, hairline rules, one accent per state. The interface is a
/// readout, so nothing on screen competes with the numbers.
public enum StarkTheme {
  public static let bg = Color.black
  public static let ink = Color(white: 0.91)
  public static let dim = Color(white: 0.42)
  public static let line = Color(white: 0.14)
  public static let ok = Color(red: 0.49, green: 0.83, blue: 0.63)
  public static let warn = Color(red: 0.88, green: 0.75, blue: 0.38)
  public static let bad = Color(red: 0.88, green: 0.48, blue: 0.42)

  public static let mono = Font.system(.footnote, design: .monospaced)
  public static let monoSmall = Font.system(.caption2, design: .monospaced)
  public static let monoBig = Font.system(size: 26, weight: .regular, design: .monospaced)
}

/// Uppercase, letter-spaced label used above every value.
struct StarkLabel: View {
  let text: String
  var body: some View {
    Text(text.uppercased())
      .font(StarkTheme.monoSmall)
      .tracking(1.4)
      .foregroundStyle(StarkTheme.dim)
  }
}

struct StatTile: View {
  let label: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(value).font(StarkTheme.monoBig).foregroundStyle(StarkTheme.ink)
      StarkLabel(text: label)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(StarkTheme.bg)
  }
}

/// Bar chart with no axes, no grid and no legend — the shape is the message.
struct Sparkline: View {
  let values: [Int]

  var body: some View {
    GeometryReader { geometry in
      let peak = max(1, values.max() ?? 1)
      HStack(alignment: .bottom, spacing: 2) {
        ForEach(Array(values.enumerated()), id: \.offset) { _, value in
          Rectangle()
            .fill(value > 0 ? StarkTheme.ink : Color(white: 0.19))
            .frame(height: max(1, geometry.size.height * CGFloat(value) / CGFloat(peak)))
        }
      }
    }
    .frame(height: 36)
  }
}

struct Pill: View {
  let text: String
  var color: Color = StarkTheme.dim

  var body: some View {
    Text(text.uppercased())
      .font(StarkTheme.monoSmall)
      .tracking(1.1)
      .foregroundStyle(color)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .overlay(Rectangle().stroke(color.opacity(0.45), lineWidth: 1))
  }
}

struct Hairline: View {
  var body: some View { Rectangle().fill(StarkTheme.line).frame(height: 1) }
}

extension ConnectionHealth.State {
  var tint: Color {
    switch self {
    case .ok: StarkTheme.ok
    case .degraded: StarkTheme.warn
    case .unauthorized, .offline: StarkTheme.bad
    }
  }
}

extension Draft.Status {
  var tint: Color {
    switch self {
    case .sent: StarkTheme.ok
    case .blocked, .failed: StarkTheme.bad
    case .pending, .approved: StarkTheme.ink
    case .rejected: StarkTheme.dim
    }
  }
}
#endif
