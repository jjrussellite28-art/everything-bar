import 'dart:io';

import 'tiles.dart';

/// Starts apps and opens links for the home screen, and runs power actions.
class Launcher {
  static String expand(String text) => text.replaceAllMapped(
    RegExp(r'%([^%]+)%'),
    (m) => Platform.environment[m.group(1)!] ?? m.group(0)!,
  );

  /// Returns null on success, or a short message when it could not start.
  static Future<String?> open(ShellTile tile) async {
    try {
      final target = expand(tile.target.trim());
      if (target.isEmpty) return 'This tile has no app or link yet.';
      if (tile.kind == 'link') {
        await Process.run('cmd', ['/c', 'start', '', target]);
        return null;
      }
      final lower = target.toLowerCase();
      if (lower.endsWith('.lnk') || lower.endsWith('.url') || lower.endsWith('.bat')) {
        if (!File(target).existsSync()) return 'Not found: $target';
        await Process.run('cmd', ['/c', 'start', '', target]);
        return null;
      }
      final hasPath = target.contains('\\') || target.contains('/');
      if (hasPath && !File(target).existsSync()) {
        return 'Not found: $target\nPress the Options button (or right-click) '
            'to change where this tile points.';
      }
      final args = tile.args.trim().isEmpty
          ? <String>[]
          : tile.args.trim().split(RegExp(r'\s+'));
      await Process.start(
        target,
        args,
        mode: ProcessStartMode.detached,
        workingDirectory: hasPath ? File(target).parent.path : null,
      );
      return null;
    } catch (e) {
      return 'Could not start ${tile.name} ($e)';
    }
  }

  static Future<void> sleep() => Process.run('rundll32.exe', [
    'powrprof.dll,SetSuspendState',
    '0,1,0',
  ]);

  static Future<void> restart() => Process.run('shutdown', ['/r', '/t', '0']);

  static Future<void> shutDown() => Process.run('shutdown', ['/s', '/t', '0']);

  static Future<void> signOut() => Process.run('shutdown', ['/l']);

  /// Windows' own on-screen keyboard, for typing with a controller.
  static Future<void> screenKeyboard() async {
    try {
      await Process.start('osk.exe', const [], mode: ProcessStartMode.detached);
    } catch (_) {}
  }
}
