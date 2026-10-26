import 'dart:io';

/// Starts Everything Bar automatically when you sign in to Windows (current user
/// only — a normal "Run" entry, the same as any startup app).
class Autostart {
  static const _key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  // Windows keeps its own on/off switch for startup apps here; if it was ever
  // switched off, the Run entry is ignored until this says "on".
  static const _approved =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';
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
      if (on) {
        final r = await Process.run('reg', [
          'add', _key, '/v', _name, '/t', 'REG_SZ',
          '/d', '"${Platform.resolvedExecutable}"', '/f',
        ]);
        await Process.run('reg', [
          'add', _approved, '/v', _name, '/t', 'REG_BINARY',
          '/d', '020000000000000000000000', '/f',
        ]);
        return r.exitCode == 0;
      }
      final r = await Process.run('reg', ['delete', _key, '/v', _name, '/f']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Run at every start from the installed copy: if the startup entry went
  /// missing, was switched off by Windows, or points somewhere else, put it
  /// right (unless the user turned it off on purpose).
  static Future<void> ensure() async {
    if (!Platform.isWindows) return;
    final exe = Platform.resolvedExecutable;
    if (!exe.toLowerCase().contains(r'\homeshell\')) return; // only the installed copy
    try {
      final r = await Process.run('reg', ['query', _key, '/v', _name]);
      final ok = r.exitCode == 0 &&
          r.stdout.toString().toLowerCase().contains(exe.toLowerCase());
      final a = await Process.run('reg', ['query', _approved, '/v', _name]);
      final approved = a.exitCode != 0 || a.stdout.toString().contains('0200000000');
      if (!ok || !approved) await set(true);
    } catch (_) {}
  }
}
