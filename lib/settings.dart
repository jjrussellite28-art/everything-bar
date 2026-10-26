import 'dart:convert';
import 'dart:io';

import 'tiles.dart';

/// The button(s) that bring the bar up. Any one of three kinds can be set; the
/// bar opens when every button of any kind is held at the same time:
///  * [padMask]  – Xbox-style controller buttons (bit mask)
///  * [joyMask]  – PlayStation / generic controller buttons (bit mask)
///  * [keys]     – keyboard or remote-control keys (Windows virtual-key codes)
class ShellShortcut {
  const ShellShortcut({this.padMask = 0, this.joyMask = 0, this.keys = const []});

  final int padMask;
  final int joyMask;
  final List<int> keys;

  static const ShellShortcut guide = ShellShortcut(padMask: 0x0400);

  bool get isEmpty => padMask == 0 && joyMask == 0 && keys.isEmpty;

  Map<String, dynamic> toJson() => {'padMask': padMask, 'joyMask': joyMask, 'keys': keys};

  factory ShellShortcut.fromJson(Map<String, dynamic> j) => ShellShortcut(
    padMask: (j['padMask'] as num?)?.toInt() ?? 0,
    joyMask: (j['joyMask'] as num?)?.toInt() ?? 0,
    keys: [for (final k in (j['keys'] as List? ?? const [])) (k as num).toInt()],
  );

  static const _padNames = <int, String>{
    0x1000: 'A',
    0x2000: 'B',
    0x4000: 'X',
    0x8000: 'Y',
    0x0100: 'LB',
    0x0200: 'RB',
    0x0020: 'Back',
    0x0010: 'Start',
    0x0040: 'L3',
    0x0080: 'R3',
    0x0400: 'Guide',
    0x0001: 'D-pad up',
    0x0002: 'D-pad down',
    0x0004: 'D-pad left',
    0x0008: 'D-pad right',
  };

  static String keyName(int vk) {
    if (vk >= 0x30 && vk <= 0x39) return String.fromCharCode(vk);
    if (vk >= 0x41 && vk <= 0x5A) return String.fromCharCode(vk);
    if (vk >= 0x70 && vk <= 0x87) return 'F${vk - 0x6F}';
    const names = <int, String>{
      0x08: 'Backspace', 0x09: 'Tab', 0x0D: 'Enter', 0x1B: 'Esc', 0x20: 'Space',
      0x21: 'Page up', 0x22: 'Page down', 0x23: 'End', 0x24: 'Home',
      0x25: 'Left', 0x26: 'Up', 0x27: 'Right', 0x28: 'Down', 0x2D: 'Insert', 0x2E: 'Delete',
      0x5B: 'Win', 0x5C: 'Win', 0xA0: 'Shift', 0xA1: 'Shift', 0xA2: 'Ctrl', 0xA3: 'Ctrl',
      0xA4: 'Alt', 0xA5: 'Alt', 0xA6: 'Browser back', 0xA7: 'Browser forward',
      0xAC: 'Browser home', 0xAD: 'Mute', 0xAE: 'Volume down', 0xAF: 'Volume up',
      0xB0: 'Next track', 0xB1: 'Previous track', 0xB2: 'Stop', 0xB3: 'Play/Pause',
      0xB4: 'Mail', 0xB5: 'Media select', 0x5D: 'Menu key', 0x5F: 'Sleep',
    };
    return names[vk] ?? 'Key 0x${vk.toRadixString(16).toUpperCase()}';
  }

  String describe() {
    if (isEmpty) return 'Nothing set';
    final parts = <String>[];
    if (padMask != 0) {
      parts.add(
        'Controller: ${[for (final e in _padNames.entries) if (padMask & e.key == e.key) e.value].join(' + ')}',
      );
    }
    if (joyMask != 0) {
      parts.add(
        'Pad: ${[for (var i = 0; i < 32; i++) if (joyMask & (1 << i) != 0) 'button ${i + 1}'].join(' + ')}',
      );
    }
    if (keys.isNotEmpty) {
      parts.add('Keys: ${keys.map(keyName).join(' + ')}');
    }
    return parts.join('   or   ');
  }
}

/// Shown in Settings so you can tell which version is running.
const String kAppVersion = '0.3.6';

/// Saved in %APPDATA%\HomeShell\settings.json.
class ShellSettings {
  ShellSettings._();
  static final ShellSettings instance = ShellSettings._();

  ShellShortcut shortcut = ShellShortcut.guide;

  /// How long the shortcut must be held, in milliseconds (0 = just press).
  int holdMs = 1000;

  /// Pause the app behind the bar while the bar is open.
  bool freeze = true;

  /// Keep the app you left paused until you switch back to it.
  bool keepFrozen = true;

  /// Keep the bar on screen all the time (it shrinks to just icons when you
  /// are using another app). Turn off to hide it after each use.
  bool pinned = false;

  /// Start-with-Windows was switched on automatically the first time.
  bool autostartDone = false;

  /// The user switched "Start with Windows" off on purpose.
  bool autostartOff = false;

  static File get _file => File('${TileStore.dir}\\settings.json');

  Future<void> load() async {
    try {
      if (await _file.exists()) {
        final j = jsonDecode(await _file.readAsString());
        if (j is Map) {
          if (j['shortcut'] is Map) {
            shortcut = ShellShortcut.fromJson(Map<String, dynamic>.from(j['shortcut'] as Map));
          }
          holdMs = (j['holdMs'] as num?)?.toInt() ?? holdMs;
          freeze = j['freeze'] as bool? ?? freeze;
          keepFrozen = j['keepFrozen'] as bool? ?? keepFrozen;
          pinned = j['pinned'] as bool? ?? pinned;
          autostartDone = j['autostartDone'] as bool? ?? autostartDone;
          autostartOff = j['autostartOff'] as bool? ?? autostartOff;
        }
      }
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      await Directory(TileStore.dir).create(recursive: true);
      await _file.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'shortcut': shortcut.toJson(),
          'holdMs': holdMs,
          'freeze': freeze,
          'keepFrozen': keepFrozen,
          'pinned': pinned,
          'autostartDone': autostartDone,
          'autostartOff': autostartOff,
        }),
      );
    } catch (_) {}
  }
}
