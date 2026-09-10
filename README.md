# StromSync

Flutter remote for the **StromSync** ESP32-S3 storm light. Talks to the board
over BLE (Nordic UART), and plays thunder through whatever the phone is already
using for audio.

- **Storm** — mode buttons and one-shot triggers
- **Tuning** — a slider per firmware parameter, plus `SAVE` / `LOAD` / `RESET`
- **Colour** — RGB for the bolt (`COLOR`) and the cloud (`TINT`)
- **Log** — every byte in and out, docked at the bottom of every screen

Android is the primary target. iOS builds are wired up but untested.

---

## Running it

### Prerequisites

- Flutter 3.x (developed against **3.47.3**, Dart 3.13.3)
- **Android SDK** with platform-tools, and a device with **USB debugging** on
- Android 5.0 (API 21) or newer

> **This machine is missing the Android SDK.** `flutter doctor` reports
> *"Unable to locate Android SDK"*, so `flutter run` cannot reach an Android
> device until you install it — via Android Studio, or the standalone
> command-line tools plus `flutter config --android-sdk <path>`. Everything
> else in the project is verified: `flutter analyze` is clean and all 17 tests
> pass. See [Known environment issues](#known-environment-issues).

### Run

```bash
flutter pub get
flutter devices          # confirm your phone shows up
flutter run
```

### Test

```bash
flutter test
```

Covers the write throttle (the part most likely to break the BLE link) and the
audio-delay arithmetic.

---

## How to use it

1. Power the light and wait for it to advertise as `StromSync`.
2. Turn on phone Bluetooth, open the app, press **Scan and connect**. Grant the
   permission prompts.
3. On connect the app sends `LIST`, so the tuning sliders start at the values
   the hardware is actually running — not at app-side defaults.
4. Press **GLOW** or **STORM**, or fire single bolts from the trigger buttons.

If the link drops, the app stays on the control screen and reconnects on its
own with a 1 / 2 / 4 / 8 / 10-second backoff. The status bar says what it is
doing at all times.

### Audio and the Bluetooth speaker

**The app does not connect to your speaker.** Pair it in Android's own
Bluetooth settings; the OS routes all app audio there. There is deliberately no
speaker-connection code in this project.

Thunder is scheduled *after* the BLE command goes out, because outdoors the
flash reaches you before the sound does:

```
delay = distanceDelayMs - speakerLatencyMs      (clamped to >= 0)
```

| Trigger          | Command      | Sample              | distanceDelayMs |
| ---------------- | ------------ | ------------------- | --------------- |
| STRIKE near      | `STRIKE 230` | `thunder_close.mp3` | 250             |
| STRIKE mid       | `STRIKE 175` | `thunder_mid.mp3`   | 1400            |
| STRIKE far       | `STRIKE 120` | `thunder_far.mp3`   | 4200            |
| SHEET            | `SHEET`      | `thunder_far.mp3`   | 4200            |

`speakerLatencyMs` is the slider on the Storm tab: 0–600 ms, default 200,
persisted across restarts. A2DP speakers typically buffer 150–250 ms. Raise it
if the clap lands late, lower it if the clap beats the flash.

Two notes on choices the brief left open:

- The brief named a **near** and a **far** strike. A **mid** button was added so
  the third bundled sample is reachable; delete the middle entry in `_triggers`
  in [storm_tab.dart](lib/ui/tabs/storm_tab.dart) if you don't want it.
- **SHEET** is a soft flash, not a bolt, so it plays the far/distant rumble.

### Replace the placeholder audio

`assets/audio/*.mp3` are **generated silent MP3s**, not recordings. They are
valid files so `just_audio` loads them without error, but they make no sound.
Drop in real recordings at the same three paths and re-run — no code change
needed. Keep the filenames:

```
assets/audio/thunder_close.mp3
assets/audio/thunder_mid.mp3
assets/audio/thunder_far.mp3
```

If a sample fails to load, the Storm tab says so and the trigger still fires the
light, silently.

---

## Command protocol

ASCII strings written to the RX characteristic, **one command per write, no
newline terminator**. The device answers on TX with `OK ...`, `ERR ...` or
`key=value` lines.

### Service

| Role         | UUID                                   |
| ------------ | -------------------------------------- |
| Service      | `6e400001-b5a3-f393-e0a9-e50e24dcca9e` |
| RX (write)   | `6e400002-b5a3-f393-e0a9-e50e24dcca9e` |
| TX (notify)  | `6e400003-b5a3-f393-e0a9-e50e24dcca9e` |

Writes use **write-without-response** where the characteristic advertises it,
falling back to acked writes otherwise (the log says which).

### Commands

| Command             | Argument range        | Effect                                     |
| ------------------- | --------------------- | ------------------------------------------ |
| `MODE OFF`          | —                     | Everything dark                            |
| `MODE GLOW`         | —                     | Idle cloud glow, no strikes                |
| `MODE STORM`        | —                     | Autonomous storm on the `storm_*` timings  |
| `STRIKE <energy>`   | 30–255                | One bolt; higher means closer              |
| `SHEET`             | —                     | One soft flash behind the cloud            |
| `SET <key> <value>` | see table below       | Live parameter change                      |
| `GET <key>`         | —                     | Device replies `key=value`                 |
| `LIST`              | —                     | Device dumps every parameter as `key=value`|
| `COLOR <r> <g> <b>` | 0–255 each            | Bolt colour                                |
| `TINT <r> <g> <b>`  | 0–255 each            | Cloud colour                               |
| `SAVE`              | —                     | Persist current values to flash            |
| `LOAD`              | —                     | Restore the saved values                   |
| `RESET`             | —                     | Back to firmware defaults                  |

### Tunable keys

| Key           | Range       | Slider step | Meaning                                     |
| ------------- | ----------- | ----------- | ------------------------------------------- |
| `bri`         | 0–255       | 1           | Master brightness ceiling                   |
| `glow_floor`  | 0–80        | 1           | Dimmest idle level                          |
| `glow_range`  | 0–80        | 1           | How far the idle glow breathes above floor  |
| `drift`       | 1–8         | 1           | Speed of the idle glow wander               |
| `noise_scale` | 1–40        | 1           | Spatial size of the cloud texture           |
| `fork_max`    | 0–3         | 1           | Branches off the main channel               |
| `stroke_max`  | 1–8         | 1           | Return strokes per strike (the flicker)     |
| `fade_close`  | 180–250     | 1           | Decay for high-energy bolts; higher = slower|
| `fade_far`    | 180–250     | 1           | Decay for low-energy bolts                  |
| `sheet_ratio` | 0–255       | 1           | Share of events that are sheets, not bolts  |
| `rumble_rate` | 1–20        | 1           | Frequency of the background rumble          |
| `storm_min`   | 500–10000   | 100         | Shortest gap between automatic events (ms)  |
| `storm_max`   | 2000–30000  | 100         | Longest gap between automatic events (ms)   |

Keys the device reports that have no slider here still show up read-only at the
bottom of the Tuning tab, so firmware can grow ahead of the app.

---

## Architecture

```
lib/
  main.dart                     providers, theme, connect-vs-control routing
  ble/
    storm_service.dart          ChangeNotifier: the connection, params, log
    write_throttle.dart         per-key rate limiter (unit tested)
    command_log.dart            log entry model
  audio/thunder_player.dart     three preloaded players, delayed playback
  model/
    params.dart                 the parameter table above, as data
    app_settings.dart           persisted speaker latency
  ui/
    connect_screen.dart
    control_screen.dart         tabs + status bar + docked log
    tabs/{storm,tuning,colour}_tab.dart
    widgets/{param_slider,log_panel,status_bar}.dart
```

`StormService` owns everything stateful about the link and exposes
`isConnected`, `status`, `parameters` (a parsed `Map<String, int>`) and
`send(String)`. No BLE call happens inside a `build` method; widgets call into
the service from event callbacks only.

### Write throttling

A slider's `onChanged` fires dozens of times a second. A BLE connection
interval is 15–50 ms, so an unthrottled drag floods the link and the light
stops responding.

[`WriteThrottle`](lib/ble/write_throttle.dart) keeps **at most one write per
100 ms per key** and drops the intermediate values — they are stale as soon as
the next one arrives. What makes dropping safe is that `onChangeEnd` submits
with `isFinal: true`, which always sends, so the value the finger stopped on is
guaranteed to reach the device even if it lands mid-window.

Buckets are per key (`bri`, `drift`, `COLOR`, `TINT`, …), so a brightness drag
never starves a simultaneous colour change. All writes then go through a single
serial chain, because overlapping GATT writes to one device are not safe.

Verified in [test/write_throttle_test.dart](test/write_throttle_test.dart): a
simulated 60-callback one-second drag produces ≤ 11 writes and always ends on
the final value.

### Reading replies

TX notifications are buffered and split on newlines, since one reply can span
several packets and one packet can carry several lines. A fragment left without
a newline for 60 ms is treated as a complete line, so firmware that omits the
trailing newline still parses.

Every `key=value` pair found anywhere in a line updates the parameter map — so
`bri=128`, `OK bri=128` and a multi-pair `LIST` line all work.

---

## Android setup

[`AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml) declares:

- `BLUETOOTH_SCAN` with `usesPermissionFlags="neverForLocation"` — we only ever
  look for our own peripheral
- `BLUETOOTH_CONNECT`
- `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION`, capped at
  `maxSdkVersion="30"`, because Android 11 and below refuse to return scan
  results without them
- `BLUETOOTH` / `BLUETOOTH_ADMIN`, also capped at API 30
- `uses-feature android:name="android.hardware.bluetooth_le"`

The location permissions are capped deliberately: paired with `neverForLocation`
they are redundant on Android 12+, and requesting them there is what gets an app
flagged in Play Console review. Drop the `maxSdkVersion` attributes if your
firmware ends up needing an uncapped location grant.

`minSdk` is pinned to **21** in
[build.gradle.kts](android/app/build.gradle.kts). Permissions are requested at
runtime in `StormService.requestPermissions()` before any scan.

---

## Known environment issues

Both are about this machine, not the project.

**1. No Android SDK.** `flutter doctor` reports *"Unable to locate Android
SDK"*. `flutter run` and `flutter build apk` cannot target a device until it is
installed.

**2. `flutter test` fails from the SDK's current location.** The Flutter SDK
lives at `G:\Projects\Flutter App\flutter`, and **the space in that path** breaks
the native-assets hook runner when it builds for the Windows host:

```
Building native assets for package:objective_c failed.
'G:\Projects\Flutter' is not recognized as an internal or external command
```

`objective_c` arrives transitively via `path_provider_foundation`, and the hook
runner spawns the Dart compiler without quoting the path. `flutter analyze` and
the Android build are unaffected — only the host-target build is.

Two ways around it:

- **Move the SDK to a path with no spaces** (`G:\flutter`, `C:\src\flutter`) and
  update `android/local.properties`. This is the real fix.
- **Or run through a junction**, which is how the tests in this repo were
  verified:

  ```powershell
  New-Item -ItemType Junction -Path C:\fl -Target "G:\Projects\Flutter App\flutter"
  C:\fl\bin\flutter.bat test
  ```

---

## Licence note

**`flutter_blue_plus` 2.x is not BSD-licensed.** It ships under the
FlutterBluePlus License: free for personal, nonprofit and educational use, but a
**paid commercial licence** is required for for-profit use or organisations of
15+ employees.

`StormService` calls `device.connect(license: License.nonprofit)`, which is the
correct declaration for a personal project. If this ever ships commercially,
buy the licence and change that argument to `License.commercial`. It appears
twice in [storm_service.dart](lib/ble/storm_service.dart) — in `connectTo` and
in the reconnect timer.

Pinning `flutter_blue_plus: ^1.35.0` instead keeps the old BSD licence, at the
cost of the 2.x fixes; the API this app uses is unchanged between the two.
