# LayerStudio

**Beat-maker-first phone music studio** — a lean Flutter DAW for making drums and grooves that feel good, then stacking bass / keys / guitar, mixing, and exporting.

[![CI](https://github.com/froelichwilliam77-design/layerstudio/actions/workflows/ci.yml/badge.svg)](https://github.com/froelichwilliam77-design/layerstudio/actions/workflows/ci.yml)

> Program a beat with swing and step probability · layer instruments · mix with per-track FX · export **stereo dithered WAV or MP3** or a portable `.layerstudio` project. Offline. No account.

### Why it exists
Most phone “studios” chase BandLab-scale features. LayerStudio stays focused: **excellent beat-making** inside a small DAW shell. Piano/guitar are available; we are **not** building AI drummer, live-loops marketplace, cloud sync, or Autotune.

### Snapshot (1.2.0)
| | |
|---|---|
| Drums | 12 procedural kits (trap → punk), pads + 16-step, swing, probability |
| Layers | Bass / keys / guitar + **user WAV import** |
| Structure | Pattern bank A–D, song timeline (move / resize / duplicate), undo/redo including mixer |
| Share | Stereo 16-bit/24-bit WAV · **MP3 (LAME)** · `.layerstudio` zip · all-projects backup |
| Play | Lock-screen / notification transport · MIDI in + clock BPM · mic punch-in / overdub |
| Platforms | Android (signed APK via CI when secrets set) · iOS (CocoaPods + unsigned CI artifact) |

**Try it:** clone → `flutter pub get` → `flutter run` (see [Run](#run)). Screenshots / demo GIF welcome in PRs — drop them under `docs/` and link here.


## What’s new in 1.2.0

- **User WAV import** into the sound library (copied into app documents, tagged YOURS)
- **MP3 export** via bundled LAME (`flutter_lame_update` / dart_lame — **LGPL**) plus 16/24-bit WAV
- **Closer live/offline mixdown** — cubic pitch resample + Echo / wave-shaper / Freeverb-style chain; song mode bounces the arrangement
- **Undo** for mixer, FX, arrange clips, and project settings (plus existing note undo)
- **Arrange timeline** — drag clips, resize, duplicate, pick pattern A–D
- **Mic punch-in** from the playhead, optional **overdub mix**, per-track latency (ms)
- **Cue / PFL** in the mixer (C button + CUE mix)
- **Lock-screen / notification transport** (`audio_service`); background no longer pauses the beat
- **MIDI input** (notes + clock → BPM)
- **Onboarding** on first launch; **backup all projects** zip from Home
- Local error log file in app documents (still no crash cloud)

## What’s new in 1.1.11

- **iOS project is runnable** — CocoaPods `Podfile`, Pods xcconfigs, privacy manifest, `.layerstudio` UTI, background audio mode, dark launch screen
- **iPad share sheet** no longer crashes (popover origin)
- **Control Center / notification shade** no longer pauses the beat (`inactive` vs real background)
- Pads / keys fire on touch-down with haptics; leaving the studio saves and stops audio
- Import reads file bytes (iOS Files picker often has no path)

## What’s new in 1.1.10

- **Stereo dithered WAV export** — mixdown keeps L/R (drums + melodic Freeverb space), applies track pan, peak-normalizes, then **TPDF dither** before 16-bit stereo PCM (optional 24-bit encode path)
- Share sheet still uses `share_plus` on the exported `.wav`

## What’s new in 1.1.9

- **Tighter clocked scheduling** — sequencer / metronome oneshots schedule to swung onset (delay) instead of firing immediately when the step enters the lookahead window
- Lookahead ~60 ms; pending timers cancel on pause / stop / seek

## What’s new in 1.1.8

- **12 drum kits** (trap/boom-bap/drill/lo-fi/house/techno/synthwave/electro + rock/indie/brush/punk) with improved procedural samples
- **Stereo melodic samples** (bass/guitar/keys) so live Freeverb activates
- **Multi-root pitch banks** — nearest root + residual rate-pitch (less stretch)

## What’s new in 1.1.0

1. **Swing** (0–100%) delays even 16ths in the audio-clock scheduler  
2. **Step probability** (per-step %; long-press a lit step)  
3. **Count-in** (1–2 bars) + **metronome** locked to audio clock / swing  
4. **Undo/redo** for step grid & piano-roll note edits  
5. **Clear track / clear pattern** (undoable)  
6. **Pattern bank A/B/C/D** + copy/clear  
7. **Song arrange** — sequence pattern clips; Song mode plays them in order  
8. **Stereo drum samples** (CC0) so live Freeverb can activate  
9. **Pitch clamp** (±24 semis hard / ±12 soft warning) for rate-pitch limits  
10. **Mic track** — arm + record from playhead (WAV on device)  
11. Home banner: export your `.layerstudio` project  
12. `PRIVACY.md`, `STORE.md` draft, in-app “copy last error”  
13. **iOS unsigned CI** workflow (`build-ios.yml`)

## Features

| Area | Status |
|------|--------|
| Beat-maker: pads + 16-step + swing + probability | Working |
| Pattern bank A–D + song arrange clips | Working |
| Count-in + metronome (audio clock) | Working |
| Undo/redo (notes, mixer, arrange, meta) | Working |
| Piano roll / keyboard / guitar chords | Working (supporting, not expanded) |
| Mixer + live per-track FX + cue PFL | Working (see Known limits) |
| Mic punch-in / overdub + latency offset | Working (not sample-accurate) |
| User WAV sample import | Working |
| Local save + `.layerstudio` import/export + zip backup | Working |
| Export WAV / MP3 share | Working (stereo 16-bit TPDF dithered WAV, 24-bit WAV, MP3 192k) |
| Lock-screen / notification transport | Working |
| MIDI in + clock tempo | Working (device support varies) |
| First-launch onboarding | Working |
| CI analyze + test | Working |
| Android release-signed APKs | Working (when secrets set) |
| iOS unsigned CI artifact | Working (`Podfile` + `flutter build ios --no-codesign`; no TestFlight without Apple certs) |

## Audio engine

**[`flutter_soloud`](https://pub.dev/packages/flutter_soloud)** — low-latency multi-voice playback, rate pitch, Echo / WaveShaper / Freeverb inserts.

### Transport

- Source of truth: `AudioEngine.transportSeconds` (app Stopwatch; not SoLoud engine clock)
- Lookahead (~60 ms) finds swung onsets; `playSampleClocked` delays to exact onset before SoLoud `play`
- Timer (~8 ms) only polls UI + scheduler
- **Limit:** `flutter_soloud` ^3.5.4 has no Dart `playClocked` / `playScheduled` (those need package ≥4.1 + Flutter ≥3.41). Scheduling uses a Timer delay after preload — tighter than immediate fire, not native sample-accurate.

### Sample licenses

`assets/samples/` = original synthetic WAVs via `tool/generate_samples.py` — **CC0**.  
**12 drum kits** (trap/boom-bap/drill/lo-fi/house/techno/synthwave/electro + rock/indie/brush/punk). Drums **and melodic** packs are **stereo** (Freeverb-friendly). Melodic presets ship multi-root banks.

## Known limits

- **Clocked scheduling:** Onsets are Timer-delayed to the swung musical time on the app transport clock. Native SoLoud `playClocked` / `playScheduled` are not exposed in flutter_soloud 3.5.4 (requires package ≥4.1 / Flutter ≥3.41). Sub-buffer sample accuracy is therefore not available yet; pause/stop/seek cancel pending timers.
- **Pitch:** SoLoud uses playback-rate pitching live. Mixdown cubic-interpolates at that rate (smoother than linear). Melodic presets pick the **nearest multi-root** sample then rate-pitch residual semis. Notes are hard-clamped to ±24 semitones past the outer roots; UI warns beyond ±12 from the nearest root.
- **Reverb:** Freeverb needs stereo sources — drums and melodic samples are stereo so Freeverb can activate. Offline mix approximates Echo / wave-shaper / comb reverb; not bit-identical to SoLoud.
- **Mic record:** Punch-in from the playhead with optional overdub mix and millisecond latency offset — not sample-accurate hardware monitoring.
- **MIDI / Link:** Note in + MIDI clock BPM only. No MIDI out, no Ableton Link.
- **Store submission:** Not done — see `STORE.md`. TestFlight needs Apple certs (iOS workflow uploads **unsigned** artifacts only). No cloud account/backup.

## Privacy

See [PRIVACY.md](PRIVACY.md) — local-first, no account/cloud in this build.

## Run

```bash
git clone https://github.com/froelichwilliam77-design/layerstudio.git
cd layerstudio
flutter pub get
flutter run
```

### iOS (Mac + Xcode)

1. Install [Xcode](https://developer.apple.com/xcode/) and CocoaPods (`sudo gem install cocoapods` or Homebrew).
2. Open **`ios/Runner.xcworkspace`** (not `.xcodeproj`) after `flutter pub get`.
3. Select a **Team** under Runner → Signing & Capabilities for a physical device. Simulator does not need a paid team.
4. Run:

```bash
flutter pub get
cd ios && pod install && cd ..
flutter run -d ios
```

Unsigned CI builds (`build-ios.yml`) produce a `.app` zip for inspection only — they cannot be installed on a device or uploaded to TestFlight until Apple certificates and a provisioning profile are added.

Regenerate samples:

```bash
python3 tool/generate_samples.py
```

## CI / releases

- `.github/workflows/ci.yml` — analyze + test on PR/push to main  
- `.github/workflows/build-apk-release.yml` — workflow_dispatch / tags → signed APKs when secrets present  
- `.github/workflows/build-ios.yml` — CocoaPods + `flutter build ios --no-codesign` + artifact (no TestFlight upload)

## Project layout

```
lib/ models/ data/ services/ screens/ widgets/ theme/ utils/
assets/samples/   # drums (stereo, 12 kits) / bass / guitar / keys (stereo multi-root)
tool/generate_samples.py
mosint/           # Python email OSINT CLI (MX, WHOIS, HIBP, DeHashed, social)
PRIVACY.md  STORE.md
```

Standalone email OSINT (not part of the mobile DAW): see [`mosint/README.md`](mosint/README.md).

## License

MIT for app code. Samples under `assets/samples/` are CC0 (see `assets/samples/LICENSE`).  
MP3 encoding uses **LAME**, bundled by [`flutter_lame_update`](https://pub.dev/packages/flutter_lame_update) / `dart_lame` under the **LGPL**. The LAME source is the copy shipped with that plugin.
