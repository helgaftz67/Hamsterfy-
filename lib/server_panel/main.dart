// Entry point of the Hamsterfy Server control panel (desktop).
//
//   flutter run -d windows -t lib/server_panel/main.dart
//   flutter build windows -t lib/server_panel/main.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../ui/theme.dart';
import 'controller.dart';
import 'panel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  final sep = Platform.pathSeparator;
  // Not every system can name a Documents folder; the music then lives
  // next to the panel's own data until the user picks a folder.
  String musicHome;
  try {
    musicHome = (await getApplicationDocumentsDirectory()).path;
  } catch (_) {
    musicHome = support.path;
  }
  final controller = ServerController(
    dataDir: Directory('${support.path}${sep}server'),
    defaultMusicFolder: '$musicHome${sep}Hamsterfy Music',
  );
  await controller.load();
  runApp(ServerPanelApp(controller: controller));
  // The panel is for running the server: start it straight away.
  await controller.start();
}

class ServerPanelApp extends StatelessWidget {
  const ServerPanelApp({super.key, required this.controller});
  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hamsterfy Server',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: ServerPanel(controller: controller),
    );
  }
}
