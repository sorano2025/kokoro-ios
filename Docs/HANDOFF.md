# Stark — handoff

Everything a fresh session needs to pick this up. Read this first; `Docs/STARK.md`
has the deeper architecture and the full HTTP API.

## State as of commit 56e8e68

- Branch: `claude/iphone-automation-llm-server-se8lhm` on `sorano2025/kokoro-ios`
- CI: **green**, both jobs (`.github/workflows/swift.yml`, macOS runner)
  - `Stark (server)` — StarkCore builds, **25 tests pass**, StarkLLM/StarkUI/StarkKit build
  - `KokoroSwift (TTS)` — builds
- ~5,000 lines of Swift across 45 files under `Stark/`

**Nothing has ever run on a device.** CI compiles for macOS, so every `#if os(iOS)`
block is unverified — most importantly `StarkKit/BackgroundRefresh.swift`, the whole
`BGTaskScheduler` path. The MLX runtime has never actually loaded a model, and no
connector has ever talked to a live API. Treat all of that as unproven.

## Layout

Two SwiftPM packages in one repo. This is deliberate — see "The pin conflict".

```
Package.swift              KokoroSwift (TTS) — the original library, untouched logic
Stark/Package.swift        the server
  Sources/StarkCore/       server, router, engine, queue, connectors, guardrails,
                           metrics, voice — no MLX dependency, all tests live here
  Sources/StarkLLM/        MLX model download + generation (one file)
  Sources/StarkUI/         SwiftUI dashboard
  Sources/StarkKit/        umbrella: Stark.boot(), BGProcessingTask refresh
Examples/StarkApp/         host app entry point + Xcode setup
Examples/KokoroVoice/      Kokoro voice impl — reference only, not in any target
Docs/STARK.md              architecture + HTTP API reference
```

## The pin conflict — do not "fix" this

`MisakiSwift 1.0.6` (KokoroSwift's G2P) pins `mlx-swift` to **exactly 0.30.2**.
Every `mlx-swift-lm` release that can host an LLM needs **0.30.3+** (2.29.x needs
0.29.x). No version satisfies both, so one dependency graph cannot contain both
libraries. That is why there are two packages and why an app links one or the other.

Merging them back, or re-adding `mlx-swift-lm` to the root manifest, reproduces the
original unresolvable graph. When Misaki loosens its pin or Kokoro moves onto
`mlx-swift-lm`, they can collapse into one package and `Examples/KokoroVoice`
becomes a real target.

## What it does

Polls each connected account → filters locally → drafts a reply with an on-device
LLM → strips assistant tells → applies guardrails → queues for approval or sends.

Key files, in the order the flow touches them:

| Stage | File |
| --- | --- |
| loop, one pass | `StarkCore/Automation/AutomationEngine.swift` (`runOnce`, `poll`, `makeDraft`, `send`) |
| pre-filter | `StarkCore/Persona/GuardRails.swift` (`shouldConsider`) |
| prompt | `StarkCore/LLM/PromptBuilder.swift` |
| generation | `StarkLLM/MLXLanguageModel.swift` |
| cleanup | `StarkCore/Persona/Humanizer.swift` (`polish`) |
| verdict | `StarkCore/Persona/GuardRails.swift` (`evaluate`) |
| queue | `StarkCore/Automation/ReviewQueue.swift` |
| control surface | `StarkCore/Server/{HTTPServer,Router,APIRoutes,Console}.swift` |

## Defaults that are deliberate

Change them only if the user asks, and tell them what it means:

- `PublishingPolicy.mode` defaults to `.review` — **nothing is sent without a human tap**
- `discloseAutomation` defaults on, appending "(automated reply)"
- Rate limits: 6 replies/hour, 40/day per connection, 1 per thread per day
- `loopbackOnly` defaults on — the server is not reachable from the network
- Sensitive-topic list in `GuardRails.sensitiveTopics` blocks promotion in grief,
  medical, legal and similar threads

These exist because every connected platform bans undisclosed automated promotion at
volume. The failure mode of raising them is a banned account, not a warning.

## Next steps, in order

1. **Pull the branch**
   ```bash
   git fetch origin claude/iphone-automation-llm-server-se8lhm
   git checkout claude/iphone-automation-llm-server-se8lhm
   ```
2. **Run the logic tests** — fast, no device needed
   ```bash
   swift test --package-path Stark
   ```
3. **Build the iOS app target.** Follow `Examples/StarkApp/README.md`. Summary: new
   iOS App project, drop in `Examples/StarkApp/StarkApp.swift`, add the local package
   at **`Stark/`** (not the repo root), link `StarkKit`, iOS 18 deployment target.
   Info.plist needs `UIBackgroundModes: processing` and
   `BGTaskSchedulerPermittedIdentifiers: [stark.server.refresh]`.
4. **Build to a real device.** MLX needs the Apple silicon GPU; the simulator will not
   work. Expect this step to surface the first `#if os(iOS)` errors.
5. **First run:** MODEL pane → load `mlx-community/Qwen3-1.7B-4bit` (smallest, always
   fits) → LINKS pane → add a product → VOICE pane → paste text and hit DRAFT. That
   exercises the whole pipeline without touching a platform.
6. **Then** connect a real account (Mastodon is the easiest: instance host + access
   token with `read:notifications` and `write:statuses`).

## Open work

- **iOS-destination CI.** Add an `xcodebuild -destination 'generic/platform=iOS'`
  step so the `#if os(iOS)` code is type-checked. Free on this public repo.
- **`BackgroundRefresh.swift` is unverified** — `MainActor.assumeIsolated` inside the
  `BGTaskScheduler` handler is the risky part.
- **Connectors are untested against live APIs.** Response shapes are written from the
  documented schemas; expect decoding fixes on first contact. Watermark handling
  (`AutomationEngine.newestID`) matters — Mastodon returns newest-first, Discord
  oldest-first.
- **Voice is not wired into the pipeline.** `SystemVoice` works standalone, but no
  connector uploads media, so `OutboundPost.audioPath` is never sent anywhere.
- **MLX API drift** is confined to `StarkLLM/MLXLanguageModel.swift`. If mlx-swift-lm
  changes its generation API, that is the only file to follow.

## Traps

- `swift build` at the repo root builds **KokoroSwift**, not Stark. Stark needs
  `--package-path Stark`.
- `MLXLMCommon` exports its own `LanguageModel` protocol; StarkCore's must be named
  `StarkCore.LanguageModel` inside StarkLLM.
- Anything crossing into `ModelContainer.perform` must be `Sendable`. `GenerateResult`
  and `Chat.Message` are not — build them inside the closure.
- The API token is generated on first launch and shown on the app's STATS pane. Every
  `/api` route needs it; `/api/events` also accepts `?token=`.
- Platform tokens live in the keychain, never in the JSON state files under
  `Application Support/Stark/`.
