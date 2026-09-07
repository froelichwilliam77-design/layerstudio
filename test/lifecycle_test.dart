import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerstudio/utils/app_lifecycle_policy.dart';

void main() {
  test('Control Center inactive does not pause transport', () {
    expect(
      transportActionForLifecycle(AppLifecycleState.inactive),
      TransportLifecycleAction.none,
    );
  });

  test('paused / hidden lifecycle pauses and saves', () {
    expect(
      transportActionForLifecycle(AppLifecycleState.paused),
      TransportLifecycleAction.pauseAndSave,
    );
    expect(
      transportActionForLifecycle(AppLifecycleState.hidden),
      TransportLifecycleAction.pauseAndSave,
    );
  });

  test('resumed reactivates the audio session', () {
    expect(
      transportActionForLifecycle(AppLifecycleState.resumed),
      TransportLifecycleAction.reactivateSession,
    );
  });

  test('detached stops and saves', () {
    expect(
      transportActionForLifecycle(AppLifecycleState.detached),
      TransportLifecycleAction.stopAndSave,
    );
  });
}
