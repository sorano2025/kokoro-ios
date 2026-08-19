import Foundation
import Testing
@testable import StarkCore

private func item(id: String, thread: String = "t1", platform: PlatformKind = .mastodon) -> InboundItem {
  InboundItem(
    id: id, connectionID: "c1", platform: platform, threadID: thread,
    authorHandle: "@a", text: "text", createdAt: Date()
  )
}

@Test func watermarkTakesHighestIDRegardlessOfBatchOrder() {
  let newestFirst = [item(id: "110"), item(id: "109"), item(id: "108")]
  let oldestFirst = [item(id: "108"), item(id: "109"), item(id: "110")]
  #expect(AutomationEngine.newestID(newestFirst) == "110")
  #expect(AutomationEngine.newestID(oldestFirst) == "110")
  #expect(AutomationEngine.newestID([]) == nil)
}

@Test func watermarkComparesSnowflakesNumericallyNotLexically() {
  let ids = [item(id: "1189234000000000000"), item(id: "999234000000000000")]
  #expect(AutomationEngine.newestID(ids) == "1189234000000000000")
}

@Test func telegramRepliesAddressTheChatNotTheUpdate() {
  #expect(item(id: "42", thread: "9001", platform: .telegram).replyTarget == "9001")
  #expect(item(id: "42", thread: "9001", platform: .mastodon).replyTarget == "42")
}

@Test func chunkingSplitsLongTextOnSentenceBoundaries() {
  let text = String(repeating: "This is a sentence about rendering. ", count: 30)
  let chunks = TextChunker.chunk(text, limit: 200)
  #expect(chunks.count > 1)
  #expect(chunks.allSatisfy { $0.count <= 260 })
}
