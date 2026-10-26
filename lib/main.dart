import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'cursor_hide.dart';
import 'gamepad.dart';
import 'home_screen.dart';
import 'autostart.dart';
import 'freezer.dart';
import 'settings.dart';
import 'single_instance.dart';
import 'shell_mode.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!args.contains('--thaw') && !SingleInstance.acquire()) {
    // Already running: bring that one forward and quit.
    SingleInstance.showExisting();
    exit(0);
  }
  if (args.contains('--thaw')) {
    // Used by the uninstaller: resume anything left paused, then quit.
    Freezer.instance.resumeStale();
    exit(0);
  }
  await ShellSettings.instance.load();
  Freezer.instance.resumeStale();
  if (Platform.isWindows && !ShellSettings.instance.autostartDone) {
    // First run: start with Windows from now on (can be switched off in Settings).
    await Autostart.set(true);
    ShellSettings.instance.autostartDone = true;
    await ShellSettings.instance.save();
  }
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: 'Everything Bar',
        size: Size(640, 156),
        backgroundColor: Color(0xFF11151F),
        titleBarStyle: TitleBarStyle.hidden,
        alwaysOnTop: true,
        skipTaskbar: true,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
    // Hold Guide from any app: show the small bar on top of it.
    WindowsGamepadService.instance.onHomeRequested = () {
      ShellMode.instance.showBar();
    };
    WindowsGamepadService.instance.start();
    CursorAutoHide.instance.start();
  }
  runApp(const HomeShellApp());
  // After the window is up, so a slow registry check never delays the bar.
  if (Platform.isWindows && !ShellSettings.instance.autostartOff) {
    unawaited(Autostart.ensure());
  }
}

class HomeShellApp extends StatelessWidget {
  const HomeShellApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Everything Bar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF3B5BDB),
        scaffoldBackgroundColor: const Color(0xFF0B0E14),
      ),
      home: const HomeScreen(),
    );
  }
}
