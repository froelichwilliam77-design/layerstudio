# LayerStudio

Beginner-friendly **phone music studio** (mobile DAW) built with **Flutter + Dart**.  
BandLab / GarageBand-style flow: pick tones → draw or tap notes → stack layers → amp/FX → mix → export.

> Out of scope (intentionally): AI drummer, live-loops grid, cloud sync, AUv3, marketplace, Autotune.

## Features (MVP)

| Area | Status |
|------|--------|
| Home + New Project (BPM, key, scale, bars) | Working |
| Local save / load / autosave (JSON) | Working |
| Sound Library (preview + Add Track) | Working |
| Drum pads + 16-step sequencer | Working |
| Piano roll (draw/erase, scroll, scale lock, velocity) | Working |
| Touch keyboard + guitar chord strips | Working |
| Transport (play/pause/stop, loop, BPM) | Working |
| Mixer (vol / pan / mute / solo + FX sliders) | Working |
| Amp presets + reverb/delay (SoLoud global filters + offline mix) | Working (simple) |
| Arrange overview + loop region | Working |
| Export WAV + share sheet | Working |
| Export MP3 | Stubbed — share WAV; MP3 needs a native encoder |
| Keep screen awake while playing | Working |
| Dark studio UI + empty states | Working |

## Audio engine

**Chosen: [`flutter_soloud`](https://pub.dev/packages/flutter_soloud) (SoLoud)**

Why:
- Low-latency multi-voice sample playback (pads + sequencer), not just media-file players
- Pitch via playback rate (`setRelativePlaySpeed`) for melodic instruments
- Built-in Freeverb / Echo filters for a simple FX chain
- Architecture is isolated in `lib/services/audio_engine.dart` so a future **Oboe (Android)** / **AudioUnit (iOS)** backend can replace the SoLoud wrapper without rewriting the DAW UI

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
  services/        # AudioEngine, StudioController, ProjectStore, ExportService
  screens/         # Home, Studio, Library, Mixer
  widgets/         # Transport, pads, step seq, piano roll, keyboard, chords, mixer
  theme/           # Dark studio theme
assets/samples/    # drums / bass / guitar / keys WAV packs
```

## Requirements

- Flutter **3.35+** / Dart **3.9+** (SDK path used while building: `/workspace/flutter-sdk`)
- Xcode (for iOS) or Android Studio / SDK (for Android)
- A physical device is strongly recommended for audio latency testing

## Run

```bash
cd layerstudio
flutter pub get
flutter run            # pick a device / simulator
# or
flutter run -d <deviceId>
```

### Open in Android Studio

1. Install Flutter & Dart plugins
2. **Open** the `layerstudio` folder (not only `android/`)
3. Wait for Gradle sync → Run on emulator or device

### Open in Xcode (iOS)

```bash
cd layerstudio/ios
pod install   # if needed
open Runner.xcworkspace
```

Or from Android Studio / VS Code use the Flutter tooling to run on a simulator.

## Export & share

- **WAV**: offline mixdown in Dart (`ExportService`) → system share sheet (`share_plus`)
- **MP3**: not encoded in-app (MVP). Share the WAV and convert with a phone app / desktop tool, or add a native encoder later (e.g. LAME / MediaCodec)

Projects autosave about every 20s under the app documents directory (`layerstudio/projects/*.json`).

## Known limits

- **Bluetooth headphones**: extra buffering latency; wired / speaker is tighter
- **Mid / low-end Android**: SoLoud buffer is 1024 frames — may need raising if you hear underruns (crackles)
- **Pitch shifting** uses playback-rate (chipmunk / slowdown artifacts on large intervals) — not formant-preserving
- **FX**: live reverb/delay are **global** SoLoud filters averaged from track settings; per-track insert FX are modeled in the offline WAV export more faithfully
- **EQ / compressor**: UI values stored; live DSP is simplified (amp soft-clip + reverb/delay). Full parametric EQ/comp is a follow-up
- **Desktop/Linux host**: audio init may fail in headless CI; the UI still loads (bootstrap catches errors)
- No cloud backup — zip the project folder or export WAV for sharing

## Vertical slice to try

1. New Project → 120 BPM, key C major  
2. Sound Library → Acoustic Rock Kit → Add Track  
3. Step Seq → draw a kick/snare groove → Play  
4. Add Clean Finger Bass → Piano Roll → draw a bassline (scale lock on)  
5. Mixer → balance volumes → Export & Share WAV  

## License

App source: use freely for learning and personal projects.  
Samples: CC0 (see above).


## GitHub

Target repository: `https://github.com/froelichwilliam77-design/music-maker.` (literal repo name includes a trailing period)

If the remote is empty, from a machine with `gh` auth:

```bash
gh repo create froelichwilliam77-design/music-maker. --public --source=. --remote=origin --push
# or, if the empty repo already exists:
git init
git add .
git commit -m "Initial LayerStudio Flutter MVP"
git branch -M main
git remote add origin https://github.com/froelichwilliam77-design/music-maker..git
git push -u origin main
```

### Regenerate samples / skipped binaries

WAV sample binaries, Android/iOS launcher PNGs, and `gradle-wrapper.jar` are **not** in this GitHub push (text-only MCP uploads). Regenerate samples before running:

```bash
python3 tool/generate_samples.py
```

That writes CC0 synthetic WAVs under `assets/samples/`. For launcher icons / `gradle-wrapper.jar`, run `flutter create .` in this folder (keeps existing files) or copy from a Flutter template.
