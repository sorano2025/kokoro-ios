# StarkApp — host target setup

The package ships libraries; iOS needs an app bundle around them. Five minutes
in Xcode:

1. **File → New → Project → iOS App**, SwiftUI lifecycle, name it `StarkApp`.
2. Delete the generated `ContentView.swift` and `…App.swift`, then drag
   `StarkApp.swift` from this folder into the target.
3. **File → Add Package Dependencies → Add Local…**, pick this repository, and
   add the **StarkKit** library to the app target.
4. Set the deployment target to **iOS 18.0** and build for a **real device** —
   MLX needs the Apple silicon GPU and does not run in the simulator.
5. Signing: any personal team works. The keychain is used for platform tokens,
   so leave the default keychain sharing entitlement alone (none needed).

## Info.plist keys

| Key | Value | Why |
| --- | --- | --- |
| `UIBackgroundModes` | `processing` | lets the automation loop wake up |
| `BGTaskSchedulerPermittedIdentifiers` | `stark.server.refresh` | matches `StarkBackgroundRefresh.taskID` |
| `UIFileSharingEnabled` | `YES` (optional) | pull `metrics.json` / `queue.json` off the device |

## Reaching the console

With the app in the foreground, open Safari on the same phone and go to
`http://127.0.0.1:8137/`. The token is on the STATS pane of the app.

To drive it from a laptop, flip `loopbackOnly` to `false` in the config file
(`Application Support/Stark/config.json`) and reach the phone on its LAN
address. Do that only on a network you trust — the token is the only thing
between the server and anyone else on that Wi-Fi.

## Model files for voice replies

`KokoroVoice` needs the Kokoro weights and a voice embedding, exactly as
[KokoroTestApp](https://github.com/mlalma/KokoroTestApp) sets them up. Text
replies work without it.
