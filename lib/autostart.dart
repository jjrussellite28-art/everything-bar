import 'dart:io';

/// Starts Home Shell automatically when you sign in to Windows (current user
/// only — a normal "Run" entry, the same as any startup app).
class Autostart {
  static const _key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _name = 'HomeShell';

  static Future<bool> isEnabled() async {
    if (!Platform.isWindows) return false;
    try {
      final r = await Process.run('reg', ['query', _key, '/v', _name]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> set(bool on) async {
    if (!Platform.isWindows) return false;
    try {
      final r = on
          ? await Process.run('reg', [
              'add', _key, '/v', _name, '/t', 'REG_SZ',
              '/d', '"${Platform.resolvedExecutable}"', '/f',
            ])
          : await Process.run('reg', ['delete', _key, '/v', _name, '/f']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
