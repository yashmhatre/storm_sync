# Thunder

A Flutter thunder box for a **BanlanX SP621E** LED controller. It fires
lightning across the strip over BLE and plays the clap so it lands when it
should.

It is not a general LED remote. Every control in the app exists to shape a
thunder strike, along two axes:

- **Sound** — which sample, how sharp, how much energy, how long the rumble
  tail runs. The sound is what shapes the light, not just what plays beside it.
- **Placement** — where along the strip the bolt lands, how wide it is, and how
  fast it travels.

---

## Read this before anything else: what an SP621E can and cannot do

The SP621E has **no per-pixel addressing**. There is no command anywhere in its
protocol to light LEDs 60–107. The entire command set is:

power · pick a built-in effect · brightness · one RGB colour · effect speed ·
effect length · chip order

That has two consequences the whole app is built around.

**Placement is a dwell time, not an address.** A bolt is placed by starting one
of the controller's white sweep effects, letting the lit block travel for a
measured time, and then cutting to black. Where the block has got to when the
lights go out is what the eye reads as the bolt's position. Nothing reports the
block's real position, so this is open-loop and has to be calibrated once per
strip — see [Calibration](#calibration).

**Only the solid effect takes an arbitrary colour.** Effect `0xBE` is the only
colourable one. Every other effect has its colours baked into the effect ID, so
a coloured moving bolt is not available; the white sweeps are.

If you need genuine per-row lightning, the SP621E is the wrong hardware and the
ESP32 firmware in [firmware/](firmware/) is the right answer. That path is still
in the repo but is no longer what `main.dart` launches.

---

## The protocol

Transcribed from the [UniLED](https://github.com/monty68/uniled) Home Assistant
integration's `banlanx2.py`, which registers SP621E as
`BanlanX2(id: 0x621E, colors: 3, intmic: false)`. Implemented in
[banlanx2_protocol.dart](lib/sp621e/banlanx2_protocol.dart) and pinned by golden
tests in [banlanx2_protocol_test.dart](test/banlanx2_protocol_test.dart).

### Transport

| Role                | UUID                                   |
| ------------------- | -------------------------------------- |
| Service             | `0000ffe0-0000-1000-8000-00805f9b34fb` |
| Write **and** notify| `0000ffe1-0000-1000-8000-00805f9b34fb` |

There is no separate read characteristic — FFE1 is both handles.

**Writes must be acknowledged.** Write-without-response is accepted by the
characteristic but these controllers drop a meaningful share of it. UniLED's
source carries an explicit `# Do not use!` against the unacked path, and this
app writes with `withoutResponse: false` throughout.

The controller also accepts **one connection at a time**. If it does not appear
in a scan, close the vendor app first — for an SP621E that is **LotusLantern**.
(BanlanX is the manufacturer whose wire format it speaks, not the app you drive
it with.)

### Frames

Every command is `A0 <cmd> <payload length> <payload…>`.

| Command       | Frame                          | Range                     |
| ------------- | ------------------------------ | ------------------------- |
| Query state   | `A0 70 00`                     | —                         |
| Power         | `A0 62 01 <00\|01>`            | —                         |
| Effect        | `A0 63 01 <id>`                | see effect table          |
| Chip order    | `A0 64 01 <order>`             | —                         |
| Brightness    | `A0 66 01 <level>`             | 0–255                     |
| Effect speed  | `A0 67 01 <speed>`             | 1–10                      |
| Effect length | `A0 68 01 <length>`            | 1–150 pixels              |
| RGB           | `A0 69 04 <r> <g> <b> <level>` | 0–255 each                |
| Light mode    | `A0 6A 01 <mode>`              | 0 single, 1/2 auto-cycle  |

Identification: BanlanX's company ID is **20563** (`0x5053`, "SP"), and an
SP621E's first manufacturer-data byte is `0x0D` or `0x16`. The connect screen
marks devices matching both, because the FFE0/FFE1 pair is shared by a lot of
unrelated BLE lights.

### Status notifications

The controller pushes its state unprompted on FFE1, framed
`53 43 <packet#> <total length> <payload length>` followed by the payload:

| Byte | Meaning     | Byte | Meaning        |
| ---- | ----------- | ---- | -------------- |
| 0    | power       | 6    | effect length  |
| 1    | light mode  | 7–9  | R, G, B        |
| 2    | effect      | 10   | audio input    |
| 3    | chip order  | 11   | sensitivity    |
| 4    | brightness  | 22   | timer count    |
| 5    | effect speed|      |                |

This is the only honest source of truth about the hardware, so the app corrects
its own assumptions from it whenever one arrives.

### Effects

All 143 entries of the RGB effect table are in
[sp621e_effects.dart](lib/sp621e/sp621e_effects.dart). The four the lightning
engine draws from:

| ID     | Name                | Use                                  |
| ------ | ------------------- | ------------------------------------ |
| `0xBE` | Solid Colour        | full-strip flood; the only colourable effect |
| `0x34` | White Wave          | broadest, softest sweep              |
| `0x8D` | White Segment Spin  | a defined block, the default bolt     |
| `0x11` | White Comet         | sharp head with a fading tail         |
| `0x18` | White Meteor        | hardest restrike                      |

---

## How a strike is built

[StrikePlanner](lib/thunder/strike_planner.dart) turns a preset into a
[StrikePlan](lib/thunder/strike_plan.dart) — a list of steps, each stamped with
when it should happen — **before anything is written**. That means the timeline
can be drawn, tested and reasoned about with no light attached, and it is what
the preview graph in the editor is showing you.

A plan runs roughly: leader → main sweep (this is where placement happens) →
return stroke → restrikes → rumble tail → dark.

What the sound changes:

| Sound field  | Effect on the light                                |
| ------------ | -------------------------------------------------- |
| sharpness    | number of return strokes, and how abrupt each is; a low value also adds a leader |
| energy       | peak brightness of the main stroke                 |
| warmth       | pulls blue out of the white, so distant reads warmer |
| rumble tail  | how long a dim glow holds after the strokes        |
| sample       | the flash-to-clap gap                              |

### Timing, and why steps get dropped

[ThunderEngine](lib/thunder/thunder_engine.dart) runs the plan against a single
monotonic `Stopwatch`. Each step waits for its own absolute offset rather than
sleeping between steps, so BLE latency cannot accumulate into drift.

A step more than **45 ms** behind schedule has missed its moment, so it is
dropped rather than written — writing it would only push everything after it
further out, and the sound is already in flight. The final step is never
dropped, so the strip cannot be left lit.

Two things keep plans inside what the link can carry:

- **The planner** never schedules a step closer to the previous one than that
  step's writes take to go out (four writes for a sweep, two for a flood, at a
  ~40 ms budget each).
- **The connection** tracks what the controller was last told and elides any
  command that would change nothing. This is the single biggest saving
  available on this link, and the home screen reports the sent/skipped ratio
  after every strike.

The "Last strike" card reports what actually happened — steps executed, steps
dropped, worst lateness. If it says steps were dropped, the plan is asking for
more traffic than the link can carry: lower sharpness to widen the gaps.

### Audio sync

The sound is timed from the **main return stroke**, not from the start of the
plan — the leader is not what makes the noise.

```
delay = mainStrokeAt + distanceDelayMs - speakerLatencyMs   (clamped to >= 0)
```

`speakerLatencyMs` is the persisted setting in
[app_settings.dart](lib/model/app_settings.dart), default 200 ms. A2DP speakers
typically buffer 150–250 ms. Raise it if the clap lands late, lower it if the
clap beats the flash.

**The app does not connect to your speaker.** Pair it in Android's Bluetooth
settings; the OS routes app audio there.

---

## Calibration

Because placement is open-loop, the app needs to know how fast the lit block
travels on *your* strip. The calibration screen (ruler icon) runs a narrow white
sweep at speed 4 and asks you to press Stop when it reaches the far end. That
one measurement scales to every speed:

```
traverseMs(speed) = traverseMsAtSpeed1 / speed
dwell(position)   = traverseMs(speed) * position
```

The screen also shows, per speed, **how near the start of the strip a bolt can
be placed at all**. A sweep cannot be cut short faster than its own four
commands go out, so roughly the first 8–15% of the strip is unreachable at
middling speeds. The editor draws that dead zone in red and warns when a preset
asks for a position inside it. Raise the speed to reach nearer positions.

The speed-to-time relationship is assumed inversely proportional, which holds
well in the middle of the range. Calibrate at the speed you actually use if you
need the ends to be accurate.

---

## Running it

```bash
flutter pub get
flutter devices
flutter run
```

```bash
flutter test      # 76 tests
flutter analyze   # clean
```

Verified on this machine: `flutter analyze` is clean, all 76 tests pass, and
`flutter build apk --debug` succeeds. The two environment problems the old
README described — a missing Android SDK, and a space in the Flutter SDK path —
are both resolved; the SDK now lives at `G:\Projects\FlutterApp\flutter`.

### The audio samples

`assets/audio/` holds four clips, each trimmed to one event:

| File | Length | What it is |
| ---- | ------ | ---------- |
| `thunder_close.mp3` | 8.0 s | a close crack |
| `thunder_mid.mp3` | 8.1 s | a mid-distance clap |
| `thunder_far.mp3` | 10.4 s | a distant roll |
| `rain.mp3` | 45 s | the looping rain bed |

The originals they were cut from are kept in [audio_source/](audio_source/),
outside the bundle so they do not inflate the APK.

**Why they are short.** The source recordings were minutes of storm ambience
with the thunder buried in the middle — the close one ran 157 seconds with its
loudest moment at 123 seconds and nothing at all in the first nine. A strike
cannot follow a file like that: it would track the silence at the front. The
clips are cut so the thunder starts immediately, which is also what stops storm
mode from overlapping itself.

To swap in your own, keep the filenames and keep them short — 3 to 10 seconds,
starting on the clap. [tool/trim_mp3.py](tool/trim_mp3.py) will cut a long
recording down without re-encoding it:

```bash
python tool/trim_mp3.py audio_source/thunder_close.mp3 assets/audio/thunder_close.mp3 122020 130020
```

It copies whole MP3 frames, so the audio is bit-identical to the source and no
decoder or ffmpeg is involved. To find the numbers, drop the long file in, run
the app, and read the `[Envelope]` line it logs — it reports where the thunder
actually is.

If a clip is left long, the app copes: it locates the busiest nine seconds and
seeks playback there, so the light and the sound start at the same moment in the
storm. That is a fallback, not the intended path.

---

## Following the sound

With **Follow the sound** on, a preset's flashes come from the recording rather
than from the sharpness slider.

The samples are decoded to PCM at startup (`audio_decoder`), then run through a
[radix-2 FFT](lib/audio/fft.dart) written out in
[fft.dart](lib/audio/fft.dart) — no dependency, it is the only signal
processing here. Each 20 ms frame is reduced to three bands:

| Band | Range | What it carries | What it drives |
| ---- | ----- | --------------- | -------------- |
| low | 20–250 Hz | the rumble | a lit floor between flashes |
| mid | 250 Hz–2 kHz | body | contributes to sharpness |
| high | 2–8 kHz | the crack | the hard flashes |

Two things follow from banding it rather than tracking loudness:

- **Flashes fire on onsets in the sharp bands.** A rumble is loud for seconds
  on end and offers nothing to flash at. The cracks inside it do.
- **Sharpness sets brightness.** A crack and a low thump can be equally loud;
  the crack flashes hard and the thump gets a soft swell.

Between flashes the strip falls to the low band, not to black, so a long roll
keeps the cloud alive.

Peaks are thinned to what the link can carry, using the measured write cost, so
a fast connection gets a busy strike and a slow one degrades to the biggest hits
rather than falling behind the audio.

None of this is real time. A BLE link cannot react to audio as it plays, so the
recording is analysed up front and the light scheduled against it.

---

## Colour

A lightning channel runs at tens of thousands of kelvin, so a close strike is
blue-white — blue highest, green below it, red lowest. Distance warms it,
because air and rain scatter the blue out over a few kilometres:

| Warmth | Colour | Reads as |
| ------ | ------ | -------- |
| 0 | `(170, 205, 255)` | a close strike, cold blue-white |
| 40 | `(255, 222, 170)` | a distant strike through rain, amber |

Equal red and blue would read as magenta, which is the one thing lightning never
looks like.

**Check the channel order before judging any of this.** If the strip is wired
GRB and the controller is set to RGB, red comes out green and every colour in
the app is wrong with it. The calibration screen has Red/Green/Blue test buttons
and the six orderings — tap Red, and if the strip is not red, change the order
until it is.

---

## Layout

```
lib/
  main.dart                        providers, theme, connect-vs-home routing
  sp621e/
    banlanx2_protocol.dart         frame builders and the status parser
    sp621e_effects.dart            the 143-entry effect table
    sp621e_connection.dart         BLE link, serialised acked writes, write elision
  thunder/
    thunder_preset.dart            a sound plus a placement, persisted
    strip_calibration.dart         position <-> dwell time
    strike_plan.dart               the step model
    strike_planner.dart            preset + calibration -> timeline
    thunder_engine.dart            runs a plan on the clock, starts the audio
  ui/thunder/
    connect_screen.dart
    thunder_home.dart              presets, storm mode, last-strike report
    preset_editor.dart             sound and placement, with a live plan preview
    calibration_screen.dart
    strip_preview.dart             strip drawing and timeline graph
    log_sheet.dart                 every byte in and out
```

### Still in the repo, not wired up

The original ESP32 "StromSync" path — `lib/ble/`, `lib/ui/tabs/`,
`lib/ui/control_screen.dart`, `lib/model/`, and `firmware/` — is intact and
still compiles, but `main.dart` no longer launches it. It is the path to take if
you ever want true per-pixel lightning.

---

## Licence note

**`flutter_blue_plus` 2.x is not BSD-licensed.** It ships under the
FlutterBluePlus License: free for personal, nonprofit and educational use, but a
**paid commercial licence** is required for for-profit use or organisations of
15+ employees.

The connection declares `License.nonprofit`, which is correct for a personal
project. If this ever ships commercially, buy the licence and change that
argument in [sp621e_connection.dart](lib/sp621e/sp621e_connection.dart).
