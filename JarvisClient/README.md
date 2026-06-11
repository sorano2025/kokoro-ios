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
curl -fsSL https://open-jarvis.github.io/OpenJarvis/install.sh | bash
```

This installs `uv`, a Python virtual environment, Ollama, and a starter
model (~3 minutes on broadband). Verify it worked:

```bash
jarvis doctor
```

### Start the API server

By default `jarvis serve` only listens on `localhost`. To let your iPhone
connect, bind it to all interfaces:

```bash
jarvis serve --host 0.0.0.0 --port 8000 --engine ollama --model qwen3:8b --agent orchestrator
```

Leave this running. It exposes an OpenAI-compatible API:

| Endpoint | Purpose |
|---|---|
| `GET /health` | Health check |
| `GET /v1/models` | List models |
| `POST /v1/chat/completions` | Chat (streaming) |

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
- **Settings** (gear icon): set your Mac's IP/port, the Ollama model name,
  voice, speech rate, and system prompt. **Test Connection** checks `/health`.

---

## Permissions & networking notes

- **Microphone** / **Speech Recognition**: requested the first time you tap
  the mic button.
- **Local Network**: iOS will prompt the first time the app tries to reach
  your Mac's IP — allow it.
- The app talks to OpenJarvis over plain HTTP on your LAN. `Info.plist` sets
  `NSAllowsLocalNetworking` so this is permitted without HTTPS.

## Troubleshooting

- **"OpenJarvis server returned HTTP ..." / connection fails**: confirm
  `jarvis serve --host 0.0.0.0 ...` is running, your Mac's firewall allows it,
  and both devices are on the same network. Try the IP in a Mac browser first:
  `http://<mac-ip>:8000/health`.
- **No voices listed in Settings**: make sure both `kokoro-v1_0.safetensors`
  and `voices.npz` show "File present" in Voice Model Setup.
- **Replies aren't spoken**: check "Speak responses aloud" is on in Settings
  and a voice is selected.
