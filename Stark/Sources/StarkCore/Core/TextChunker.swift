//
//  StarkCore
//
import Foundation

/// Splits text into sentence-aligned pieces under a length limit.
///
/// Used by the voice path, where the TTS model has a hard token ceiling: a long
/// draft has to be spoken in pieces, and cutting mid-sentence is audible.
public enum TextChunker {
  public static func chunk(_ text: String, limit: Int = 400) -> [String] {
    var chunks: [String] = []
    var current = ""
    for sentence in text.split(whereSeparator: { ".!?\n".contains($0) }) {
      let piece = sentence.trimmingCharacters(in: .whitespaces)
      guard !piece.isEmpty else { continue }
      if current.count + piece.count > limit, !current.isEmpty {
        chunks.append(current)
        current = ""
      }
      current += current.isEmpty ? piece + "." : " " + piece + "."
    }
    if !current.isEmpty { chunks.append(current) }
    return chunks.isEmpty ? [text] : chunks
  }
}
