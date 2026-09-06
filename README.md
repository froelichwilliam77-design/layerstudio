# LayerStudio

Beginner-friendly **phone music studio** (mobile DAW) built with **Flutter + Dart**.  
BandLab / GarageBand-style flow: pick tones → draw or tap notes → stack layers → amp/FX → mix → export.

> Out of scope (intentionally): AI drummer, live-loops grid, cloud sync, AUv3, marketplace, Autotune.

## What’s new in 1.0.1

1. **Audio-clock sequencer** — playhead + note scheduling follow `AudioEngine` transport time with ~40 ms lookahead (Timer is only a poller).
2. **audio_session** — music playback session, interruption pause/resume policy, lifecycle-safe Play state.
3. **Project export/import** — shareable `.layerstudio` zip (JSON + embedded sample WAVs).
4. **Live per-track FX** — Echo / WaveShaper (/ Freeverb when possible) applied per voice from each track’s mixer settings.
5. **Release signing for CI** — upload keystore via GitHub secrets; release APKs signed when secrets are present.

## Features (MVP)

| Area | Status |
|------|--------|
| Home + New Project (BPM, key, scale, bars) | Working |
| Local save / load / autosave (JSON) | Working |
| **Import / export portable `.layerstudio` project** | Working |
| Sound Library (preview + Add Track) | Working |
| Drum pads + 16-step sequencer | Working |
| Piano roll (draw/erase, scroll, scale lock, velocity) | Working |
| Touch keyboard + guitar chord strips | Working |
| Transport (play/pause/stop, loop, BPM) — **audio clock** | Working |
| Mixer (vol / pan / mute / solo + FX sliders) | Working |
| Amp / reverb / delay — **live per-track inserts** + offline mix | Working (see Known limits) |
| Arrange overview + loop region | Working |
| Export WAV + share sheet | Working |
| Export MP3 | Stubbed — share WAV; MP3 needs a native encoder |
| Keep screen awake while playing | Working |
| Dark studio UI + empty states | Working |
| CI analyze + test | Working |
| Release-signed sideload APKs | Working (when secrets set) |

## Audio engine

**Chosen: [`flutter_soloud`](https://pub.dev/packages/flutter_soloud) (SoLoud)**

Why:
- Low-latency multi-voice sample playback (pads + sequencer), not just media-file players
- Pitch via playback rate (`setRelativePlaySpeed`) for melodic instruments
- Built-in Freeverb / Echo / WaveShaper filters for FX
- Architecture is isolated in `lib/services/audio_engine.dart` so a future **Oboe (Android)** / **AudioUnit (iOS)** backend can replace the SoLoud wrapper without rewriting the DAW UI

### Transport / sequencer clock

- **Source of truth:** `AudioEngine.transportSeconds` — a monotonic Stopwatch anchored when Play/Seek runs (tied to the audio engine lifecycle, not wall-clock `DateTime` drift as the scheduler).
- **Lookahead (~40 ms):** `StudioController` schedules note oneshots for steps entering `[now, now+lookahead]` so attacks are not tied to a coarse Timer tick.
- A short Timer (~8 ms) only **polls** the clock to update the UI playhead and run the lookahead scheduler.
- BPM, loop, start/stop/seek remain supported; loop wraps re-anchor the transport clock.

**Not used as the sequencer engine:** `audioplayers` / `just_audio` alone — fine for preview players, but higher latency and weaker multi-voice scheduling for a DAW.

### Sample licenses

All files under `assets/samples/` are **original synthetic WAVs** generated for this project (procedural kicks, noise hats, additive piano, Karplus-Strong-style plucks, etc.).  
**License: CC0 / public domain — free to use, modify, and redistribute** with LayerStudio.

Replace them with your own packs anytime; keep paths in `lib/data/sound_library.dart` in sync.

## Project layout

```
lib/
  main.dart
  models/          # Project, Track, NoteEvent, FxSettings
  data/            # Sound library presets
  services/        # AudioEngine, StudioController, ProjectStore, ExportService, ProjectBundle
  screens/         # Home, Studio, Library, Mixer
  widgets/         # Transport, pads, step seq, piano roll, keyboard, chords, mixer
  theme/           # Dark studio theme
  utils/           # Music theory, DSP, audio clock math
assets/samples/    # drums / bass / guitar / keys WAV packs
```

## Requirements

- Flutter **3.35+** / Dart **3.9+**
- Xcode (for iOS) or Android Studio / SDK (for Android)
- A physical device is strongly recommended for audio latency testing

## Run

Clone and run from the **repository root** (`pubspec.yaml` is at the root — do not `cd` into a nested `layerstudio` folder):

```bash
git clone https://github.com/froelichwilliam77-design/layerstudio.git
cd layerstudio
flutter pub get
flutter run            # pick a device / simulator
```

### Open in Android Studio

1. Install Flutter & Dart plugins
2. **Open** the repository root (the folder that contains `pubspec.yaml`, not only `android/`)
3. Wait for Gradle sync → Run on emulator or device

### Open in Xcode (iOS)

From the repository root:

```bash
cd ios
pod install   # if needed
open Runner.xcworkspace
```

## Export & share

### Mixdown (WAV)

- **WAV**: offline mixdown in Dart (`ExportService`) → system share sheet (`share_plus`)
- **MP3**: not encoded in-app (MVP). Share the WAV and convert externally, or add a native encoder later

### Portable project (`.layerstudio`)

- **Export:** Studio app bar → folder-zip icon, or share a `.layerstudio` archive (ZIP containing `project.json` + `samples/` WAVs referenced by the project).
- **Import:** Home → upload icon → pick a `.layerstudio` / `.zip` file → project is restored into the local store and opened.
- Autosave JSON under app documents (`layerstudio/projects/*.json`) remains as-is for day-to-day editing.

## Android release signing (sideload)

This repo **does not** publish to Play Store. Goal: **release-signed APKs** you can sideload.

### Local `key.properties` (gitignored)

```properties
storePassword=***
keyPassword=***
keyAlias=layerstudio
storeFile=app/upload-keystore.jks
```

Place `key.properties` under `android/` and the `.jks` at `android/app/upload-keystore.jks` (both gitignored).  
`android/app/build.gradle.kts` reads `key.properties` **or** env vars:
`ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.

If none are present, release builds **fall back to debug signing** with a Gradle warning.

### CI secrets

Workflow `.github/workflows/build-apk-release.yml` expects:

| Secret | Purpose |
|--------|---------|
| `ANDROID_KEYSTORE_BASE64` | base64 of the upload `.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_KEY_PASSWORD` | key password |

On `workflow_dispatch` / `v*` tags it decodes the keystore, writes `android/key.properties`, and builds **release** APKs. Missing secrets → clear warning + debug-signing fallback.

Generate a keystore once (do **not** commit it):

```bash
keytool -genkeypair -v -keystore upload-keystore.jks -alias layerstudio \
  -keyalg RSA -keysize 2048 -validity 10000
base64 -w0 upload-keystore.jks | gh secret set ANDROID_KEYSTORE_BASE64
# similarly set ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD
```

## Known limits

- **Bluetooth headphones**: extra buffering latency; wired / speaker is tighter
- **Mid / low-end Android**: SoLoud buffer is 1024 frames — may need raising if you hear underruns (crackles)
- **Pitch shifting** uses playback-rate (chipmunk / slowdown artifacts on large intervals) — not formant-preserving
- **Live FX / SoLoud inserts**:
  - Delay + amp use **per-AudioSource** Echo + WaveShaper with **per-handle** params from the triggering track (honest per-note settings).
  - Freeverb insert requires **stereo** sources; bundled samples are **mono**, so Freeverb activate often no-ops — live “reverb” then blends extra Echo wet/decay as space. Offline WAV export still uses its own per-track reverb/delay taps.
  - Tracks that share the same loaded sample share one AudioSource filter chain (params still set per voice handle).
  - SoLoud does not expose true multi-bus insert racks; this is the best honest mapping.
- **EQ / compressor**: UI values stored; live DSP is simplified (amp waveshaper + echo/reverb). Full parametric EQ/comp is a follow-up
- **Desktop/Linux host**: audio init may fail in headless CI; the UI still loads (bootstrap catches errors)
- **Interruptions**: pause on interrupt / becoming-noisy; resume after interrupt when we paused for that reason. Backgrounding pauses and does **not** auto-resume (Play stays honest).

## Vertical slice to try

1. New Project → 120 BPM, key C major  
2. Sound Library → Acoustic Rock Kit → Add Track  
3. Step Seq → draw a kick/snare groove → Play  
4. Add Clean Finger Bass → Piano Roll → draw a bassline (scale lock on)  
5. Mixer → set per-track reverb/delay → Export WAV or Export project  

## License

- **App source:** [MIT](LICENSE) — Copyright (c) 2026 William Froelich
- **Samples** under `assets/samples/`: [CC0 / public domain](assets/samples/LICENSE) (see Sample licenses above)

## GitHub

Repository: [`https://github.com/froelichwilliam77-design/layerstudio`](https://github.com/froelichwilliam77-design/layerstudio)

```bash
git clone https://github.com/froelichwilliam77-design/layerstudio.git
cd layerstudio
flutter pub get
flutter run
```

Releases / source: https://github.com/froelichwilliam77-design/layerstudio

If you need to regenerate synthetic sample WAVs locally:

```bash
python3 tool/generate_samples.py
```

That writes CC0 synthetic WAVs under `assets/samples/`.
