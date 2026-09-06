# LayerStudio

**Beat-maker first** phone music studio (Flutter mobile DAW).  
Make drums and groove excellent inside a lean DAW shell — piano/guitar stay available, but we are **not** expanding toward a full BandLab clone (no AI drummer, live-loops marketplace, cloud sync, Autotune, etc.).

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
| Undo/redo (notes / clear) | Working |
| Piano roll / keyboard / guitar chords | Working (supporting, not expanded) |
| Mixer + live per-track FX | Working (see Known limits) |
| Mic arm → record take → playback | Working (not sample-accurate punch-in) |
| Local save + `.layerstudio` import/export | Working |
| Export WAV share | Working |
| Export MP3 | Stubbed |
| CI analyze + test | Working |
| Android release-signed APKs | Working (when secrets set) |
| iOS unsigned CI artifact | Working (no TestFlight without Apple certs) |

## Audio engine

**[`flutter_soloud`](https://pub.dev/packages/flutter_soloud)** — low-latency multi-voice playback, rate pitch, Echo / WaveShaper / Freeverb inserts.

### Transport

- Source of truth: `AudioEngine.transportSeconds`
- Lookahead (~40 ms) schedules swung onsets
- Timer (~8 ms) only polls UI + scheduler

### Sample licenses

`assets/samples/` = original synthetic WAVs via `tool/generate_samples.py` — **CC0**.  
**12 drum kits** (trap/boom-bap/drill/lo-fi/house/techno/synthwave/electro + rock/indie/brush/punk). Drums **and melodic** packs are **stereo** (Freeverb-friendly). Melodic presets ship multi-root banks.

## Known limits

- **Pitch:** SoLoud uses playback-rate pitching. Melodic presets pick the **nearest multi-root** sample then rate-pitch residual semis (less stretch than a single root). Notes are hard-clamped to ±24 semitones past the outer roots; UI warns beyond ±12 from the nearest root.
- **Reverb:** Freeverb needs stereo sources — drums and melodic samples are stereo so Freeverb can activate. Not a convolution hall.
- **Mic record:** Armed-track capture from playhead, not sample-accurate punch-in / overdub.
- **Song arrange:** Simple clip list (pattern + start bar + length), not a full DAW playlist editor.
- **MP3 export:** Not in-app.
- **Store submission:** Not done — see `STORE.md`. TestFlight needs Apple certs (iOS workflow uploads **unsigned** artifacts only).

## Privacy

See [PRIVACY.md](PRIVACY.md) — local-first, no account/cloud in this build.

## Run

```bash
git clone https://github.com/froelichwilliam77-design/layerstudio.git
cd layerstudio
flutter pub get
flutter run
```

Regenerate samples:

```bash
python3 tool/generate_samples.py
```

## CI / releases

- `.github/workflows/ci.yml` — analyze + test on PR/push to main  
- `.github/workflows/build-apk-release.yml` — workflow_dispatch / tags → signed APKs when secrets present  
- `.github/workflows/build-ios.yml` — `flutter build ios --no-codesign` + artifact (no TestFlight upload)

## Project layout

```
lib/ models/ data/ services/ screens/ widgets/ theme/ utils/
assets/samples/   # drums (stereo, 12 kits) / bass / guitar / keys (stereo multi-root)
tool/generate_samples.py
PRIVACY.md  STORE.md
```

## License

MIT for app code. Samples under `assets/samples/` are CC0 (see `assets/samples/LICENSE`).
