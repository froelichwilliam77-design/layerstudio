import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
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
      home: const HomeScreen(),
    );
  }
}
