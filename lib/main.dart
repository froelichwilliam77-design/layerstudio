import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/studio_controller.dart';
import 'theme/studio_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  final controller = StudioController();
  try {
    await controller.bootstrap();
  } catch (e, st) {
    debugPrint('Bootstrap warning (audio may be unavailable on this host): $e\n$st');
  }

  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: const LayerStudioApp(),
    ),
  );
}

class LayerStudioApp extends StatelessWidget {
  const LayerStudioApp({super.key});

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
