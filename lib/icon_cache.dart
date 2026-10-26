import 'dart:convert';
import 'dart:io';

import 'tiles.dart';

/// Gets the real icon of a program (as a small PNG) and keeps it in
/// %APPDATA%\HomeShell\icons so it only has to be made once.
class IconCache {
  IconCache._();
  static final IconCache instance = IconCache._();

  final Map<String, Future<File?>> _pending = {};

  static String _key(String path) {
    var h = 5381;
    for (final c in path.toLowerCase().codeUnits) {
      h = ((h << 5) + h + c) & 0x7fffffff;
    }
    return h.toRadixString(16);
  }

  /// Returns the icon file, or null if it could not be made.
  Future<File?> iconFor(String exePath) {
    if (exePath.isEmpty) return Future.value(null);
    return _pending.putIfAbsent(exePath, () => _make(exePath));
  }

  Future<File?> _make(String exePath) async {
    try {
      final dir = Directory('${TileStore.dir}\\icons');
      await dir.create(recursive: true);
      final out = File('${dir.path}\\${_key(exePath)}.png');
      if (await out.exists() && await out.length() > 0) return out;
      if (!File(exePath).existsSync()) return null;
      const script =
          r'Add-Type -AssemblyName System.Drawing; '
          r'$i=[System.Drawing.Icon]::ExtractAssociatedIcon($env:HS_IN); '
          r'if($i){$b=$i.ToBitmap(); $b.Save($env:HS_OUT,[System.Drawing.Imaging.ImageFormat]::Png)}';
      final encoded = base64.encode(
        // PowerShell wants UTF-16LE for -EncodedCommand.
        [for (final u in script.codeUnits) ...[u & 0xff, u >> 8]],
      );
      await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-EncodedCommand', encoded],
        environment: {'HS_IN': exePath, 'HS_OUT': out.path},
      ).timeout(const Duration(seconds: 15));
      if (await out.exists() && await out.length() > 0) return out;
    } catch (_) {}
    return null;
  }
}
