# Play Store listing draft (checklist — not submitted)

> This is a **draft checklist** for a future Play Console listing.  
> **Status: not submitted.** Creating a Play Console account and uploading an AAB/APK is out of scope for the app repo alone.

## App identity
- **Title:** LayerStudio
- **Short description (≤80 chars):** Beat-maker first phone studio — drums, swing, patterns, mix & export.
- **Full description (draft):**
  LayerStudio is a beginner-friendly mobile music studio with a beat-maker-first focus.
  Program drum grooves with swing and step probability, stack bass/keys/guitar layers,
  arrange A/B/C/D patterns into a simple song timeline, mix with per-track FX, and export
  WAV or a portable `.layerstudio` project. Works offline. No account required.

## Assets still needed
- [ ] Feature graphic (1024×500)
- [ ] Hi-res icon (512×512) — app icon exists; export store-sized PNG
- [ ] Phone screenshots (≥2): Home, Step sequencer + swing, Arrange/song mode, Mixer
- [ ] Optional tablet screenshots

## Content rating / policy notes
- Music creation tool; no user-generated social feed in-app.
- Microphone permission: declare for recording vocals/ideas into a track.
- No gambling, no violence, no target audience under 13 required beyond standard.

## Build / signing
- Use release-signed AAB/APK from GitHub Actions when upload keystore secrets are set.
- Package name: keep consistent with `applicationId` in `android/app/build.gradle`.

## Do not claim
- Do not mark “published on Play” until Console shows production/open testing live.
