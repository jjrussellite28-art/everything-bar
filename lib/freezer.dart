import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show File, Platform, pid;

import 'package:flutter/foundation.dart';

import 'open_windows.dart';
import 'tiles.dart';

/// Pauses the app that was in front when the bar opened, so a game doesn't
/// keep reacting to the controller (or keep running) behind the bar. It is
/// resumed when the bar hides. If Home Shell ever closes unexpectedly, the next
/// start resumes anything it left paused.
class Freezer {
  Freezer._();
  static final Freezer instance = Freezer._();

  bool _ready = false;
  late final int Function(int, int, int) _openProcess;
  late final int Function(int) _closeHandle;
  late final int Function(int) _suspend;
  late final int Function(int) _resume;
  final Set<int> _frozen = <int>{};

  static File get _file => File('${TileStore.dir}\\frozen.json');

  static const _neverFreeze = {
    'explorer.exe',
    'applicationframehost.exe',
    'shellexperiencehost.exe',
    'searchhost.exe',
    'startmenuexperiencehost.exe',
    'textinputhost.exe',
    'dwm.exe',
    'sihost.exe',
    'taskmgr.exe',
    'lockapp.exe',
    'steamwebhelper.exe',
    'gamebar.exe',
    'gamebarftserver.exe',
    'xboxpcapp.exe',
    'discord.exe',
    'home_shell.exe',
    'everything bar.exe',
  };

  bool _init() {
    if (_ready) return true;
    if (kIsWeb || !Platform.isWindows) return false;
    try {
      final k = DynamicLibrary.open('kernel32.dll');
      _openProcess = k.lookupFunction<
        IntPtr Function(Uint32, Int32, Uint32),
        int Function(int, int, int)
      >('OpenProcess');
      _closeHandle = k.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
      final n = DynamicLibrary.open('ntdll.dll');
      _suspend = n.lookupFunction<Int32 Function(IntPtr), int Function(int)>('NtSuspendProcess');
      _resume = n.lookupFunction<Int32 Function(IntPtr), int Function(int)>('NtResumeProcess');
      _ready = true;
    } catch (e) {
      debugPrint('Freezer unavailable: $e');
    }
    return _ready;
  }

  int _act(int processId, int Function(int) fn) {
    final h = _openProcess(0x0800, 0, processId); // PROCESS_SUSPEND_RESUME
    if (h == 0) return -1;
    try {
      return fn(h);
    } finally {
      _closeHandle(h);
    }
  }

  void _persist() {
    try {
      _file.writeAsStringSync(jsonEncode(_frozen.toList()));
    } catch (_) {}
  }

  /// Call once at start: resume anything a previous run left paused.
  void resumeStale() {
    if (!_init()) return;
    try {
      if (_file.existsSync()) {
        final list = jsonDecode(_file.readAsStringSync());
        if (list is List) {
          for (final p in list) {
            _act((p as num).toInt(), _resume);
          }
        }
        _file.deleteSync();
      }
    } catch (_) {}
  }

  /// Pauses the program that is in front right now (if it is safe to).
  void freezeForeground() {
    if (!_init()) return;
    _current = 0;
    final p = OpenWindows.instance.foregroundPid();
    if (p == 0 || p == pid) return;
    final exe = OpenWindows.instance.exeOf(p).toLowerCase();
    if (exe.isEmpty) return;
    final name = exe.split('\\').last;
    if (_neverFreeze.contains(name)) return;
    if (_frozen.contains(p)) return;
    if (_act(p, _suspend) == 0) {
      _frozen.add(p);
      _current = p;
      _persist();
    }
  }

  /// The program that was paused when the bar opened.
  int _current = 0;

  bool isFrozen(int processId) => processId != 0 && _frozen.contains(processId);

  /// Resumes one program. Always do this BEFORE asking Windows to switch to
  /// its window: switching to a paused window makes the bar wait on it.
  void thawPid(int processId) {
    if (!_ready || !_frozen.remove(processId)) return;
    _act(processId, _resume);
    if (_current == processId) _current = 0;
    _persist();
  }

  void thawWindow(int hwnd) => thawPid(OpenWindows.instance.pidOf(hwnd));

  /// Resumes only the program that was in front when the bar opened.
  void thawCurrent() {
    if (_current != 0) thawPid(_current);
  }

  void thawAll() {
    if (!_ready || _frozen.isEmpty) return;
    for (final p in _frozen.toList()) {
      _act(p, _resume);
    }
    _frozen.clear();
    _current = 0;
    try {
      if (_file.existsSync()) _file.deleteSync();
    } catch (_) {}
  }
}
