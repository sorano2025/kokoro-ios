# Kokoro TTS for Swift

✨ *New in 1.0.8:* Added timestamps for each token. Please check [Kokoro Test App](https://github.com/mlalma/KokoroTestApp) how to use them.

✨ *New in 1.0.5:* Voice styles are moved out of the library to the integrating application. Please check [Kokoro Test App](https://github.com/mlalma/KokoroTestApp) how to use them.

Kokoro is a high-quality TTS (text-to-speech) model, providing faster than real-time English audio generation.

*NOTE:* This is a SPM package of the TTS engine. For an application integrating Kokoro and showing how the neural speech synthesis works, please see [KokoroTestApp](https://github.com/mlalma/KokoroTestApp) project.

Kokoro TTS port is based on the great work done in [MLX-Audio project](https://github.com/Blaizzy/mlx-audio), where the model was ported from PyTorch to MLX Python. This project ports the MLX Python code to MLX Swift.

Currently the library generates audio ~3.3 times faster than real-time on the release build on iPhone 13 Pro after warm up / first run.

## Requirements

- iOS 18.0+
- macOS 15.0+
- (Other Apple platforms may work as well)

## Installation

Add KokoroSwift to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/mlalma/kokoro-ios.git", from: "1.0.0")
]
```

Then add it to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "KokoroSwift", package: "kokoro-ios")
    ]
)
```

## Usage

```swift
import KokoroSwift

// Initialize the TTS engine
let modelPath = URL(fileURLWithPath: "path/to/your/model")
let tts = KokoroTTS(modelPath: modelPath, g2p: .misaki)

// Generate speech
let voiceEmbedding = ... // See KokoroTestApp on how to get a voice style as an `MLXArray`
let text = "Hello, this is a test of Kokoro TTS."
let audioBuffer = try tts.generateAudio(voice: voiceEmbedding, language: .enUS, text: text)

// audioBuffer now contains the synthesized speech
```

## G2P (Grapheme-to-Phoneme) Options

- `.misaki` - MisakiSwift, default G2P processor
- `.espeak` - eSpeakNG, an alternative G2P processor (commented out in current version)

## Model Files

You'll need to provide your own Kokoro TTS model file due to its large size as well as voice style. Please see example project [Kokoro Test App](https://github.com/mlalma/KokoroTestApp) how they can be included as a part of the application package.

## Dependencies

This package depends on:
- [MLX Swift](https://github.com/ml-explore/mlx-swift) - Apple's MLX framework for Swift
- [MisakiSwift](https://github.com/mlalma/MisakiSwift) - G2P processor
- [MLXUtilsLibrary](https://github.com/mlalma/MLXUtilsLibrary) - Utility library

## Stark — on-device automation server

This repository also carries `Stark`, an automation server that runs inside an
iOS app: an HTTP control surface on the loopback interface, an MLX-hosted
language model downloaded on demand, platform connectors, and a review queue
with rate limits and disclosure defaults. Kokoro is wired in for voice replies.

It is a **separate SwiftPM package** under [`Stark/`](Stark): MisakiSwift pins
mlx-swift to 0.30.2 while the LLM runtime needs 0.30.3+, so the two cannot share
a dependency graph. An app links one or the other.

- Products: `StarkKit` (everything), `StarkCore` (no MLX, fully testable)
- Docs: [Docs/STARK.md](Docs/STARK.md)
- Host app: [Examples/StarkApp](Examples/StarkApp)

```swift
let server = try await Stark.boot()   // server + model runtime + loop
StarkDashboard(server: server)        // the tiny stark interface
```

## License

This project is licensed under MIT License - see the [LICENSE](LICENSE) file for details.