import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/studio_audio_handler.dart';
import 'services/studio_controller.dart';
import 'theme/studio_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  final controller = StudioController();
  final handler = StudioAudioHandler(
    onPlay: controller.play,
    onPause: controller.pause,
    onStop: controller.stop,
  );
  controller.attachAudioHandler(handler);

  final inTest = _runningUnderFlutterTest();
  if (!inTest) {
    try {
      await AudioService.init(
        builder: () => handler,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.layerstudio.audio',
          androidNotificationChannelName: 'LayerStudio',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
    } catch (e) {
      debugPrint('AudioService.init skipped: $e');
    }
  }

  try {
    await controller.bootstrap();
  } catch (e, st) {
    debugPrint(
      'Bootstrap warning (audio may be unavailable on this host): $e\n$st',
    );
  }

  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: LayerStudioApp(controller: controller),
    ),
  );
}

bool _runningUnderFlutterTest() {
  try {
    return Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

class LayerStudioApp extends StatefulWidget {
  const LayerStudioApp({super.key, required this.controller});

  final StudioController controller;

  @override
  State<LayerStudioApp> createState() => _LayerStudioAppState();
}

class _LayerStudioAppState extends State<LayerStudioApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.controller.onAppLifecycle(state);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LayerStudio',
      debugShowCheckedModeBanner: false,
      theme: buildStudioTheme(),
      home: widget.controller.onboarded
          ? const HomeScreen()
          : OnboardingScreen(
              onDone: () async {
                await widget.controller.completeOnboarding();
                if (context.mounted) setState(() {});
              },
            ),
    );
  }
}
