import Foundation
import Testing
@testable import StarkCore

private let persona = Persona(targetWords: 10...40, emojiBudget: 0)
private let publishing = PublishingPolicy(mode: .review, discloseAutomation: true, disclosureText: "(automated reply)")
private let humanizer = Humanizer(persona: persona, publishing: publishing)

@Test func stripsAssistantOpenerAndMarkdown() {
  let polished = humanizer.polish("""
  Certainly! Here is what I would do:

  - **Check** the export settings
  - Then re-render
  """)
  #expect(!polished.lowercased().hasPrefix("certainly"))
  #expect(!polished.contains("**"))
  #expect(!polished.contains("- "))
}

@Test func stripsReasoningBlock() {
  let polished = humanizer.polish("<think>the user wants X</think>Try the export panel first.")
  #expect(polished.hasPrefix("Try the export panel"))
}

@Test func appendsDisclosureExactlyOnce() {
  let once = humanizer.polish("Use the batch exporter, it handles that case.")
  #expect(once.contains("(automated reply)"))
  let twice = humanizer.polish(once)
  let occurrences = twice.components(separatedBy: "(automated reply)").count - 1
  #expect(occurrences == 1)
}

@Test func trimsToWordBudgetAtSentenceBoundary() {
  let long = Array(repeating: "word", count: 30).joined(separator: " ") + ". " + Array(repeating: "extra", count: 40).joined(separator: " ") + "."
  let polished = humanizer.polish(long)
  #expect(polished.split(separator: " ").count <= persona.targetWords.upperBound + 2)
}

@Test func dropsEmojiWhenBudgetIsZero() {
  let polished = humanizer.polish("That export bug is fixed in 2.1 🎉🎉")
  #expect(!polished.contains("🎉"))
}

@Test func similarityCatchesRecycledReplies() {
  let first = "The batch exporter handles that, it queues the renders and writes them out overnight."
  let second = "The batch exporter handles that, it queues the renders and writes them out at night."
  let unrelated = "Have you tried restarting the machine and clearing the cache directory first?"
  #expect(Humanizer.similarity(first, second) > 0.5)
  #expect(Humanizer.similarity(first, unrelated) < 0.2)
}
