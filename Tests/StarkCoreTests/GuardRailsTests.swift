import Foundation
import Testing
@testable import StarkCore

private func item(_ text: String) -> InboundItem {
  InboundItem(
    id: "1", connectionID: "c1", platform: .mastodon, threadID: "t1",
    authorHandle: "@someone", text: text, createdAt: Date()
  )
}

private let product = DigitalProduct(
  name: "Renderbox",
  pitch: "batch video rendering for solo editors",
  url: "https://example.com/renderbox",
  keywords: ["render", "export", "editing"]
)

private func rails(_ mode: PublishingPolicy.Mode = .autoWithinGuardrails) -> GuardRails {
  GuardRails(
    limits: RateLimits(),
    persona: Persona(),
    publishing: PublishingPolicy(mode: mode, discloseAutomation: false)
  )
}

@Test func skipsMessagesWithNoRelevantProduct() {
  let (ok, reason) = rails().shouldConsider(item("anyone know a good pizza place downtown?"), products: [product])
  #expect(!ok)
  #expect(reason != nil)
}

@Test func skipsSensitiveThreadsEvenWhenKeywordsMatch() {
  let (ok, _) = rails().shouldConsider(item("my brother died last week, I still have his render project open"), products: [product])
  #expect(!ok)
}

@Test func acceptsRelevantQuestion() {
  let (ok, _) = rails().shouldConsider(item("what do people use to batch export renders overnight?"), products: [product])
  #expect(ok)
}

@Test func blocksWhenHourlyLimitReached() {
  let verdict = rails().evaluate(
    draft: "Renderbox does overnight batches.",
    item: item("how do I batch export?"),
    recentSent: [],
    sentLastHourOnConnection: 6,
    sentTodayOnConnection: 6,
    sentTodayInThread: 0
  )
  #expect(verdict.decision == .block)
}

@Test func blocksDuplicateOfRecentReply() {
  let draft = "Renderbox queues the renders and writes them out overnight, that is what I use."
  let verdict = rails().evaluate(
    draft: draft,
    item: item("how do I batch export?"),
    recentSent: [draft],
    sentLastHourOnConnection: 0, sentTodayOnConnection: 0, sentTodayInThread: 0
  )
  #expect(verdict.decision == .block)
}

@Test func blocksSecondReplyInSameThread() {
  let verdict = rails().evaluate(
    draft: "Try the batch exporter.",
    item: item("how do I batch export?"),
    recentSent: [],
    sentLastHourOnConnection: 0, sentTodayOnConnection: 0, sentTodayInThread: 1
  )
  #expect(verdict.decision == .block)
}

@Test func holdsUnverifiableClaimsForReview() {
  let verdict = rails().evaluate(
    draft: "It is guaranteed to cut your render time by 90%.",
    item: item("how do I batch export?"),
    recentSent: [],
    sentLastHourOnConnection: 0, sentTodayOnConnection: 0, sentTodayInThread: 0
  )
  #expect(verdict.decision == .review)
}

@Test func reviewModeNeverAutoSends() {
  let verdict = rails(.review).evaluate(
    draft: "Try the batch exporter, it queues renders overnight.",
    item: item("how do I batch export?"),
    recentSent: [],
    sentLastHourOnConnection: 0, sentTodayOnConnection: 0, sentTodayInThread: 0
  )
  #expect(verdict.decision == .review)
}

@Test func missingDisclosureIsHeldForReview() {
  let strict = GuardRails(
    limits: RateLimits(),
    persona: Persona(),
    publishing: PublishingPolicy(mode: .autoWithinGuardrails, discloseAutomation: true, disclosureText: "(automated reply)")
  )
  let verdict = strict.evaluate(
    draft: "Try the batch exporter, it queues renders overnight.",
    item: item("how do I batch export?"),
    recentSent: [],
    sentLastHourOnConnection: 0, sentTodayOnConnection: 0, sentTodayInThread: 0
  )
  #expect(verdict.decision == .review)
}

@Test func productRelevanceIgnoresNegativeKeywords() {
  #expect(product.relevance(to: "best way to export a render?") > 0)
  #expect(product.relevance(to: "I want a refund for this render tool") == 0)
}
