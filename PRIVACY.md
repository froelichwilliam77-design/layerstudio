# Privacy — LayerStudio

LayerStudio is **local-first**.

## What we collect
- **Nothing by default.** There is no account system, analytics SDK, or cloud sync in this app build.
- Projects and autosaves stay on your device (app documents storage).
- Optional `.layerstudio` / WAV / MP3 exports leave the device only when **you** use the system share sheet.
- A local `error_log.txt` may be written under app documents when something fails (no upload).

## Permissions
| Permission | Why |
|------------|-----|
| **Microphone** (optional) | Record into a mic track. Audio is written to a local WAV on your device. |
| **Audio / media playback** | Play samples, metronome, mixes, and lock-screen / notification transport. |
| **Bluetooth** (optional) | Connect MIDI devices. |

## What we do not do
- No sign-in / no cloud project backup unless a future build adds it and this doc is updated.
- No ad network.
- No Firebase / crash cloud pipeline in the default build (in-app “copy last error” only).

## Contact
See the GitHub repository for issues: https://github.com/froelichwilliam77-design/layerstudio
