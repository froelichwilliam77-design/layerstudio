# Play Store listing draft (checklist — not submitted)

> This is a **draft checklist** for a future Play Console listing.  
> **Status: not submitted.** Creating a Play Console account and uploading an AAB/APK is out of scope for the app repo alone.

## App identity
- **Title:** LayerStudio
- **Short description (≤80 chars):** Beat-maker first phone studio — drums, swing, patterns, mix & export.
- **Full description (draft):**
  LayerStudio is a beginner-friendly mobile music studio with a beat-maker-first focus.
  Program drum grooves with swing and step probability, stack bass/keys/guitar layers,
  arrange A/B/C/D patterns into a song timeline, mix with per-track FX, and export
  WAV, MP3, or a portable `.layerstudio` project. Works offline. No account required.

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

---

# App Store listing draft (checklist — not submitted)

> Draft only. TestFlight / App Store Connect upload needs an Apple Developer Program membership, signing certificates, and a provisioning profile. The repo’s `build-ios.yml` produces an **unsigned** `.app` for CI inspection, not an IPA you can submit.

## App identity
- **Name:** LayerStudio
- **Bundle ID:** `com.layerstudio.layerstudio`
- **Subtitle (≤30 chars):** Beat-maker phone studio
- **Category:** Music
- **Privacy:** See `PRIVACY.md` — local-first, microphone only for optional mic tracks.

## iOS project (done in 1.1.11)
- [x] CocoaPods `ios/Podfile` + Pods xcconfigs
- [x] `NSMicrophoneUsageDescription`
- [x] `UIBackgroundModes` = audio
- [x] Privacy manifest (`PrivacyInfo.xcprivacy`)
- [x] `ITSAppUsesNonExemptEncryption` = false
- [x] `.layerstudio` document type / UTI
- [ ] Apple Developer Team selected in Xcode (Signing & Capabilities)
- [ ] Archive → Distribute / TestFlight

## Assets still needed
- [ ] App Store icon 1024×1024 (no alpha) — marketing icon exists in `ios/Runner/Assets.xcassets`
- [ ] iPhone screenshots (6.7" and 6.1") for Home, Beat, Mixer
- [ ] Optional iPad screenshots

## Do not claim
- Do not mark “on the App Store” or “available on TestFlight” until App Store Connect shows a build.

