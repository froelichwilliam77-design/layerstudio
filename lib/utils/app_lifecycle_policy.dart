import 'package:flutter/widgets.dart' show AppLifecycleState;

/// What the studio transport should do for an [AppLifecycleState].
enum TransportLifecycleAction {
  none,
  saveOnly,
  pauseAndSave,
  stopAndSave,
  reactivateSession,
}

/// iOS Control Center / notification shade send [AppLifecycleState.inactive]
/// without leaving the app — pausing there would kill a playing beat.
///
/// [paused] / [hidden] keep playback going so lock-screen / Now Playing
/// controls still drive the mix; we only persist the project.
TransportLifecycleAction transportActionForLifecycle(AppLifecycleState state) {
  return switch (state) {
    AppLifecycleState.inactive => TransportLifecycleAction.none,
    AppLifecycleState.paused ||
    AppLifecycleState.hidden => TransportLifecycleAction.saveOnly,
    AppLifecycleState.resumed => TransportLifecycleAction.reactivateSession,
    AppLifecycleState.detached => TransportLifecycleAction.stopAndSave,
  };
}
