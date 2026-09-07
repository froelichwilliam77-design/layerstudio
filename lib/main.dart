import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'reddit_archive_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const TraceArchiveApp());
}
