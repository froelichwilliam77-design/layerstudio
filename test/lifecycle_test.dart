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

  test('paused / hidden lifecycle saves but keeps playing for lock screen', () {
    expect(
      transportActionForLifecycle(AppLifecycleState.paused),
      TransportLifecycleAction.saveOnly,
    );
    expect(
      transportActionForLifecycle(AppLifecycleState.hidden),
      TransportLifecycleAction.saveOnly,
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
