# Stark — an automation server that runs on the phone

An HTTP server, a local language model and a reply pipeline, all inside one iOS
app. Nothing it does requires a backend: the weights, the queue, the metrics and
the platform tokens stay on the device.

```
             ┌──────────────────────── iPhone ────────────────────────┐
Safari ─────▶│  HTTPServer (Network.framework, loopback :8137)        │
laptop ─ ─ ─▶│      └─ Router ─ APIRoutes ─┐                          │
             │                             ▼                          │
             │  AutomationEngine ── ReviewQueue ── MetricsStore        │
             │      │        │                                        │
             │      │        └── GuardRails ── Humanizer ── Persona    │
             │      │                                                 │
             │      ├── PlatformConnector × N  ──▶ mastodon/discord/…  │
             │      ├── LanguageModel                                  │
             │      │      └─ MLXLanguageModel (MLX, GPU)             │
             │      └── VoiceSynthesizer ── SystemVoice (AVFoundation)│
             └────────────────────────────────────────────────────────┘
```

## Targets

Stark is its own SwiftPM package under `Stark/`, separate from the KokoroSwift
package at the repository root.

| Target | Depends on | Contains |
| --- | --- | --- |
| `StarkCore` | Foundation, Network, Security, AVFoundation | server, router, engine, queue, connectors, guardrails, metrics, voice |
| `StarkLLM` | MLX, mlx-swift-lm | model download + generation |
| `StarkUI` | StarkCore, SwiftUI | the native dashboard |
| `StarkKit` | all three | `Stark.boot()`, background refresh |

`StarkCore` deliberately has no MLX dependency: it is the part with the logic
worth testing, and it compiles and runs its tests in seconds.

### Why two packages

`MisakiSwift`, the grapheme-to-phoneme library KokoroSwift needs, pins
`mlx-swift` to **exactly 0.30.2**. Every `mlx-swift-lm` release that can host a
language model needs **0.30.3 or newer** (2.29.x wants 0.29.x). No version of
`mlx-swift` satisfies both, so SwiftPM cannot resolve a graph containing both
libraries — this is why the repository's own HEAD dropped Misaki when it added
`mlx-swift-lm`.

Separate packages let each resolve. An app links one or the other: `StarkKit`
for the server, `KokoroSwift` for TTS. When Misaki loosens its pin (or Kokoro
moves onto `mlx-swift-lm`), the two collapse back into one package and
`Examples/KokoroVoice` becomes a real target.

## The loop

1. **Poll** every enabled connection for mentions/DMs since the last watermark.
2. **Filter** — length, sensitive topics, product relevance. No model pass for
   traffic that was never going to get a reply.
3. **Triage** — for borderline matches, a 4-token `REPLY`/`SKIP` call.
4. **Draft** — persona + product facts + limitations + the thread, generated
   on-device.
5. **Humanize** — strip assistant tells, markdown, throat-clearing and length
   overrun; append the disclosure line.
6. **Judge** — rate limits, duplicate detection, link count, claim check.
7. **Queue or send** — `review` (default), `autoWithinGuardrails`, or `dryRun`.
   Sends are spaced by `minSecondsBetweenSends` plus jitter.

## What "humanized" means here

Replies that read like a person wrote them: short, specific, contraction-heavy,
no bullet lists, no "Great question!". What it does not mean is pretending to be
a person. Automated posts carry a disclosure line by default, the persona is
forbidden from inventing personal experiences, and the guardrails hold anything
that makes a claim the product facts do not support.

That default is not decoration. Every platform worth connecting bans
undisclosed automated promotion, and the ceilings in `RateLimits` — 6 replies
an hour, 40 a day, one per thread — are set where an account survives. Raise
them and the failure mode is a ban, not a warning.

## HTTP API

All `/api` routes need `Authorization: Bearer <token>`; `/api/events` also
accepts `?token=`. The token is generated on first launch and shown in the app.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/` | dashboard |
| GET | `/api/health` | liveness, unauthenticated |
| GET | `/api/stats` | metrics, model status, connections, device limits |
| GET | `/api/logs` `?limit=` | recent log lines |
| GET | `/api/events` | SSE live log |
| GET/PATCH | `/api/config` | mode, tick, persona, limits, sampling |
| GET | `/api/models` | catalog, what fits this device, load status |
| POST | `/api/models/load` | `{"id":"mlx-community/Qwen3-4B-4bit"}`, returns 202 |
| POST | `/api/models/unload` | free the weights |
| GET/POST | `/api/connections` | list / add (token goes to the keychain) |
| DELETE | `/api/connections/:id` | remove connection and credential |
| POST | `/api/connections/:id/verify` | check the credential |
| POST | `/api/connections/:id/toggle` | pause / resume |
| GET/POST | `/api/products` | promoted products |
| DELETE | `/api/products/:id` | remove |
| GET | `/api/queue` `?status=` | drafts |
| POST | `/api/queue/:id/approve` | optional `{"text":"edited"}`, then sends |
| POST | `/api/queue/:id/reject` | discard |
| POST | `/api/run` | one pass now |
| POST | `/api/engine/start` \| `/stop` | control the loop |
| POST | `/api/draft` | `{"text":"…"}` — draft against pasted text, sends nothing |

## Models

`ModelCatalog` lists MLX-community conversions from 1.7B to 24B. The catalog is
a starting point — any repo id `LLMModelFactory` accepts will load.

Size is bounded by the per-app memory limit, not by the device's RAM.
`DeviceCapability.memoryBudgetGB` reads `os_proc_available_memory()`, which is
the number that decides whether a load survives, and `DeviceCapability.check`
refuses a download that will not fit before it spends the bandwidth. Rough
shape: 6 GB phones run 3B comfortably, 8 GB phones run 4B, 12 GB run 8B, and
14B+ wants a 16 GB iPad or a Mac.

Weights land in `Documents/huggingface` — the location the MLX model factory
resumes partial downloads from — with the iCloud backup flag cleared, so a
13 GB model never turns into a 13 GB backup.

## What iOS will not let this do

- **No background socket.** The listener stops when the app is suspended. The
  console is reachable while the app is in the foreground (or briefly after).
- **Background passes are the system's call.** `BGProcessingTask` typically
  fires while charging on Wi-Fi, often only a few times a day. Continuous
  polling means the app stays open.
- **No simulator.** MLX needs the real GPU.
- **Thermals.** Sustained generation throttles a phone in minutes. The pacing
  delays help; a 4B model on a warm device is still slower than the first run
  suggests.

## Connectors

`MastodonConnector`, `TelegramConnector`, `DiscordConnector` and
`WebhookConnector` ship. `GenericRESTConnector` covers anything else with a
JSON spec — inbox URL, dotted paths to the fields, and a send template — so a
new platform is a config change, not a rebuild.

All of them use documented APIs with a token the account owner pastes in.
Scraping or driving a logged-in web session is out of scope: it breaks the terms
of every one of these platforms and gets the account banned.

## State on disk

`Application Support/Stark/`: `config.json`, `connections.json`,
`products.json`, `queue.json`, `metrics.json`. Platform tokens are in the
keychain (`kSecAttrAccessibleAfterFirstUnlock`), never in those files.

## Voice

`VoiceSynthesizer` renders a draft to an audio file on the device.
`SystemVoice` implements it with AVSpeechSynthesizer — no dependency, no
download, available the moment the app launches. `Examples/KokoroVoice` holds
the higher-quality Kokoro implementation, which conforms to the same protocol
and drops in once the dependency pins above allow it.

None of the shipped connectors upload media, so audio is a utility rather than
part of the reply pipeline today.

## Testing

`swift test --package-path Stark --filter StarkCoreTests` covers the parts worth pinning down:
request parsing, routing, JSON path extraction, HTML stripping, the humanizer's
subtractions and every guardrail decision. None of it needs a model, a network
or a device.
