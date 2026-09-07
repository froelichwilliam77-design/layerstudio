import '../models/project.dart';
import '../models/track.dart';

/// Live-monitor routing (mute / solo / cue PFL). Export ignores cue.
bool isTrackAudible(
  Track track, {
  required StudioProject project,
  bool honorCue = true,
}) {
  if (track.muted) return false;
  final anySolo = project.tracks.any((t) => t.solo);
  if (anySolo && !track.solo) return false;
  if (honorCue && project.cueMode) {
    final anyCue = project.tracks.any((t) => t.cue);
    if (anyCue && !track.cue) return false;
  }
  return true;
}
