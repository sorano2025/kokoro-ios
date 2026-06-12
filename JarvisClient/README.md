# Jarvis Client (iOS) + OpenJarvis (Mac)

A voice assistant for iPhone: your **MacBook** runs [OpenJarvis](https://github.com/open-jarvis/OpenJarvis)
(a local LLM + agents, served over your Wi-Fi), and this **iOS app** is the
voice front-end — it listens on-device, sends your request to OpenJarvis,
streams the reply, and speaks it back using the Kokoro TTS engine from this
repo, fully on-device.

```
 ┌────────────────────┐        Wi-Fi / LAN        ┌──────────────────────────┐
 │   iPhone (this app) │ ───── HTTP / SSE ────────▶│   MacBook (OpenJarvis)    │
 │                     │◀──── streamed reply ──────│  jarvis serve --host 0.0.0.0│
 │  • on-device STT    │                           │  --port 8000              │
 │  • Kokoro TTS       │                           │  (Ollama + local LLM)     │
 └────────────────────┘                           └──────────────────────────┘
```

Nothing in this setup requires the cloud: the LLM runs locally on your Mac via
Ollama, and speech-to-text/text-to-speech run locally on your iPhone.

---

## 1. Set up OpenJarvis on your Mac

OpenJarvis is a separate, Mac/Linux/Windows desktop project (Apache 2.0,
Stanford Hazy Research). Install it with the one-command installer:

```bash
curl -fsSL https://raw.githubusercontent.com/open-jarvis/OpenJarvis/main/scripts/install/install.sh | bash
```

> The project's docs also advertise
> `https://open-jarvis.github.io/OpenJarvis/install.sh` as a shorter URL for
> the same script, but that GitHub Pages site currently 404s. The
> `raw.githubusercontent.com` URL above points at the same canonical script
> (`scripts/install/install.sh` in the repo) and works today. If the Pages
> URL starts working for you, both are equivalent.

This installs `uv`, a Python virtual environment, Ollama, and a starter
model (~3 minutes on broadband). Verify it worked:

```bash
jarvis doctor
```

### Install the API server extra

`jarvis serve` needs FastAPI/uvicorn, which the base install doesn't include.
Install them into the same venv the installer created:

```bash
cd ~/.openjarvis/src
uv pip install --python ~/.openjarvis/.venv/bin/python -e ".[server]"
```

(If you used a custom `OPENJARVIS_HOME`, substitute it for `~/.openjarvis`.)

### Generate an API key

`jarvis serve` refuses to bind to a non-`localhost` address (like
`0.0.0.0`, which your iPhone needs) unless an API key is configured:

```bash
jarvis auth create-key
```

This prints something like `API key generated: oj_sk_...` and stores it in
`~/.openjarvis/config.toml` under `[server.auth]`. Copy this key — you'll
paste it into the iOS app's Settings as the **API key**.

### Pick a model

`jarvis doctor` lists the Ollama models you already have (e.g.
`llama3.2:1b`, `phi4-mini:latest`, `qwen2.5-coder:7b`). Use one of those for
`--model` below, or pull a new one first with `ollama pull qwen3:8b`.

### Start the API server

By default `jarvis serve` only listens on `localhost`. To let your iPhone
connect, bind it to all interfaces:

```bash
jarvis serve --host 0.0.0.0 --port 8000 --engine ollama --model qwen2.5-coder:7b --agent orchestrator
```

Leave this running. It exposes an OpenAI-compatible API:

| Endpoint | Purpose | Auth |
|---|---|---|
| `GET /health` | Health check | none |
| `GET /v1/models` | List models | `Authorization: Bearer <api key>` |
| `POST /v1/chat/completions` | Chat (streaming) | `Authorization: Bearer <api key>` |

The iOS app sends the `Authorization` header automatically once you've
entered the API key in Settings.

### Find your Mac's local IP address

You'll enter this in the iOS app's settings.

```bash
ipconfig getifaddr en0
```

(If you're on Wi-Fi via a different interface, try `en1`, or check
**System Settings → Wi-Fi → Details → IP Address**.)

Make sure your Mac's firewall allows incoming connections for `jarvis`
(System Settings → Network → Firewall), and that your iPhone is on the
**same Wi-Fi network** as your Mac.

---

## 2. Build the iOS app

The app lives in this `JarvisClient/` directory as an [XcodeGen](https://github.com/yonaskolb/XcodeGen)
project so the `.xcodeproj` doesn't need to be committed.

### Prerequisites (on your Mac)

```bash
brew install xcodegen
```

You'll also need Xcode 16+ (for iOS 18 SDK) and an Apple ID signed into
Xcode (free account is fine for running on your own device).

### Generate and open the project

```bash
cd JarvisClient
xcodegen generate
open JarvisClient.xcodeproj
```

This wires up three Swift package dependencies automatically:
- `KokoroSwift` (this repo, via a local path dependency)
- `MLXUtilsLibrary` (for loading voice packs)
- `mlx-swift` (MLX / MLXNN)

### Configure signing

In Xcode, select the `JarvisClient` target → **Signing & Capabilities** →
pick your personal team. Plug in your iPhone (or select it as the run
destination) and hit **Run**. The first run will ask you to trust the
developer certificate on your iPhone (**Settings → General → VPN & Device
Management**).

---

## 3. Set up Kokoro's voice model on the iPhone

Kokoro's model weights and voice packs are too large to bundle with the app,
so the app downloads/imports them once into its Documents directory. On
first launch, a **Voice Model Setup** sheet appears.

### `kokoro-v1_0.safetensors`

The setup screen is pre-filled with a URL to the community MLX port:

```
https://huggingface.co/mlx-community/Kokoro-82M-bf16/resolve/main/kokoro-v1_0.safetensors
```

Tap **Download Now**. If that URL ever 404s (repo layouts change), open the
link in Safari on your Mac, find the `.safetensors` file under "Files and
versions", copy its `resolve/main/...` URL, and paste it into the field — or
download it on your Mac and use **Import from Files…** after AirDropping it
to your iPhone.

### `voices.npz`

Voice packs aren't published as a single file, so generate one yourself on
your Mac with the included script:

```bash
cd JarvisClient/Scripts
pip install torch numpy huggingface_hub
python build_voices_npz.py --output voices.npz
```

This downloads a handful of Kokoro voices (`af_heart`, `af_bella`, `am_adam`,
`bf_emma`, `bm_george`, ...) from `hexgrad/Kokoro-82M` and packs them into
`voices.npz`. AirDrop `voices.npz` to your iPhone, then in the Voice Model
Setup screen tap **Import from Files…** under "voices.npz" and select it.

Once both files are present, the app loads them and the **Voice** picker in
Settings fills in with the voices you included.

---

## 4. Using Jarvis

- Tap the **mic button** to talk — speech is transcribed on-device
  (`SFSpeechRecognizer`, `requiresOnDeviceRecognition`) and sent
  automatically when you stop.
- Or type a message and hit send.
- Replies stream in from OpenJarvis and are spoken aloud sentence-by-sentence
  via Kokoro as they arrive.
- **Settings** (gear icon): set your Mac's IP/port, the **API key** from
  `jarvis auth create-key`, the Ollama model name, voice, speech rate, and
  system prompt. **Test Connection** checks `/health` and `/v1/models`
  (which also confirms the API key is correct).

---

## 5. Using Jarvis away from home with Tailscale (optional)

By default, the iPhone and Mac need to be on the same Wi-Fi network. To reach
your Mac's OpenJarvis server from anywhere (e.g. at work or on cellular)
without exposing it to the public internet, use
[Tailscale](https://tailscale.com) — a free private WireGuard network.

1. Install Tailscale on your Mac (`brew install --cask tailscale` or the Mac
   App Store) and on your iPhone (App Store), and sign in to the same
   Tailscale account on both.
2. On your Mac, find its Tailscale MagicDNS name:
   ```bash
   tailscale status
   ```
   It looks like `mymac.tailxxxxx.ts.net`.
3. Keep `jarvis serve --host 0.0.0.0 --port 8000 ...` running, and make sure
   your Mac doesn't go to sleep (e.g. run it under `caffeinate -s`, or disable
   sleep in System Settings → Lock Screen/Energy).
4. In the iOS app's **Settings**, enter the Tailscale MagicDNS name (without
   `http://`) as the **Server** field instead of your LAN IP. Port, API key,
   and model stay the same.

This works because `Info.plist` adds an ATS exception allowing plain HTTP to
`*.ts.net` addresses specifically — Tailscale's MagicDNS names aren't covered
by iOS's normal "local networking" exception, which only covers private LAN
IP ranges.

---

## Permissions & networking notes

- **Microphone** / **Speech Recognition**: requested the first time you tap
  the mic button.
- **Local Network**: iOS will prompt the first time the app tries to reach
  your Mac's IP — allow it.
- The app talks to OpenJarvis over plain HTTP. `Info.plist` sets
  `NSAllowsLocalNetworking` for LAN addresses, plus an exception for
  `*.ts.net` (Tailscale MagicDNS) so this is permitted without HTTPS in both
  cases.

## Troubleshooting

- **"OpenJarvis server returned HTTP ..." / connection fails**: confirm
  `jarvis serve --host 0.0.0.0 ...` is running, your Mac's firewall allows it,
  and both devices are on the same network. Try the IP in a Mac browser first:
  `http://<mac-ip>:8000/health`.
- **"Server dependencies not installed"**: run
  `uv pip install --python ~/.openjarvis/.venv/bin/python -e ".[server]"`
  from `~/.openjarvis/src` (see step 1 above).
- **`jarvis serve --host 0.0.0.0 ...` exits immediately / "requires
  OPENJARVIS_API_KEY"**: run `jarvis auth create-key` on your Mac and enter
  the printed key in the app's Settings → **API key**.
- **HTTP 401 from the app / "Connected, but the API key is missing or
  incorrect"**: re-run `jarvis auth create-key` (it overwrites the stored
  key) and update Settings with the new value.
- **No voices listed in Settings**: make sure both `kokoro-v1_0.safetensors`
  and `voices.npz` show "File present" in Voice Model Setup.
- **Replies aren't spoken**: check "Speak responses aloud" is on in Settings
  and a voice is selected.
