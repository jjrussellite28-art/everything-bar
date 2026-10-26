import 'dart:ffi';
import 'dart:io' show Platform, pid;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// One open program window.
class OpenWindow {
  OpenWindow(this.hwnd, this.title, [this.exePath = '']);
  final int hwnd;
  final String title;

  /// Full path of the program's .exe ('' when unknown).
  final String exePath;
}

/// Lists the programs that are open on Windows, switches to one, or closes one.
class OpenWindows {
  OpenWindows._();
  static final OpenWindows instance = OpenWindows._();

  bool _ready = false;
  late final int Function(int, int, int) _openProcess;
  late final int Function(int, int, Pointer<Uint16>, Pointer<Uint32>) _queryImage;
  late final int Function(int) _closeHandle;
  late final int Function(Pointer<NativeFunction<Int32 Function(IntPtr, IntPtr)>>, int) _enumWindows;
  late final int Function(int) _isVisible;
  late final int Function(int) _isIconic;
  late final int Function(int, Pointer<Uint16>, int) _getText;
  late final int Function(int) _getTextLen;
  late final int Function(int, int) _getWindow;
  late final int Function(int, int) _getLong;
  late final int Function(int, Pointer<Uint32>) _getPid;
  late final int Function() _foreground;
  late final int Function(int, int) _showWindow;
  late final int Function(int) _setForeground;
  late final int Function(int, int, int, int) _postMessage;
  late final void Function(int, int, int, int) _keybdEvent;
  late final int Function(int, int, Pointer<Int32>, int) _dwmGet;

  void _init() {
    if (_ready) return;
    final u = DynamicLibrary.open('user32.dll');
    _enumWindows = u
        .lookupFunction<
          Int32 Function(Pointer<NativeFunction<Int32 Function(IntPtr, IntPtr)>>, IntPtr),
          int Function(Pointer<NativeFunction<Int32 Function(IntPtr, IntPtr)>>, int)
        >('EnumWindows');
    _isVisible = u.lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsWindowVisible');
    _isIconic = u.lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsIconic');
    _getText = u.lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint16>, Int32),
      int Function(int, Pointer<Uint16>, int)
    >('GetWindowTextW');
    _getTextLen = u.lookupFunction<Int32 Function(IntPtr), int Function(int)>('GetWindowTextLengthW');
    _getWindow = u.lookupFunction<IntPtr Function(IntPtr, Uint32), int Function(int, int)>('GetWindow');
    _getLong = u.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('GetWindowLongW');
    _getPid = u.lookupFunction<
      Uint32 Function(IntPtr, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>)
    >('GetWindowThreadProcessId');
    _foreground = u.lookupFunction<IntPtr Function(), int Function()>('GetForegroundWindow');
    _showWindow = u.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('ShowWindow');
    _setForeground = u.lookupFunction<Int32 Function(IntPtr), int Function(int)>('SetForegroundWindow');
    _postMessage = u.lookupFunction<
      Int32 Function(IntPtr, Uint32, IntPtr, IntPtr),
      int Function(int, int, int, int)
    >('PostMessageW');
    _keybdEvent = u.lookupFunction<
      Void Function(Uint8, Uint8, Uint32, IntPtr),
      void Function(int, int, int, int)
    >('keybd_event');
    _dwmGet = DynamicLibrary.open('dwmapi.dll').lookupFunction<
      Int32 Function(IntPtr, Uint32, Pointer<Int32>, Uint32),
      int Function(int, int, Pointer<Int32>, int)
    >('DwmGetWindowAttribute');
    final k = DynamicLibrary.open('kernel32.dll');
    _openProcess = k.lookupFunction<
      IntPtr Function(Uint32, Int32, Uint32),
      int Function(int, int, int)
    >('OpenProcess');
    _queryImage = k.lookupFunction<
      Int32 Function(IntPtr, Uint32, Pointer<Uint16>, Pointer<Uint32>),
      int Function(int, int, Pointer<Uint16>, Pointer<Uint32>)
    >('QueryFullProcessImageNameW');
    _closeHandle = k.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
    _ready = true;
  }

  static final List<int> _found = <int>[];

  static int _collect(int hwnd, int lParam) {
    _found.add(hwnd);
    return 1;
  }

  /// Full path of a program's .exe from its process id ('' if unknown).
  String exeOf(int processId) {
    if (!Platform.isWindows) return '';
    try {
      _init();
    } catch (_) {
      return '';
    }
    final h = _openProcess(0x1000, 0, processId); // QUERY_LIMITED_INFORMATION
    if (h == 0) return '';
    final buf = calloc<Uint16>(1024);
    final size = calloc<Uint32>()..value = 1024;
    try {
      if (_queryImage(h, 0, buf, size) == 0) return '';
      return buf.cast<Utf16>().toDartString();
    } finally {
      calloc.free(buf);
      calloc.free(size);
      _closeHandle(h);
    }
  }

  /// Open program windows, skipping this app and Windows' own background ones.
  List<OpenWindow> list() {
    if (!Platform.isWindows) return const [];
    try {
      _init();
      _found.clear();
      final cb = NativeCallable<Int32 Function(IntPtr, IntPtr)>.isolateLocal(
        _collect,
        exceptionalReturn: 0,
      );
      try {
        _enumWindows(cb.nativeFunction, 0);
      } finally {
        cb.close();
      }
      final out = <OpenWindow>[];
      final pidBuf = calloc<Uint32>();
      final cloaked = calloc<Int32>();
      try {
        for (final h in _found) {
          if (_isVisible(h) == 0) continue;
          if (_getWindow(h, 4) != 0) continue; // owned popup windows
          final ex = _getLong(h, -20);
          if (ex & 0x80 != 0) continue; // tool windows
          final len = _getTextLen(h);
          if (len <= 0) continue;
          _dwmGet(h, 14, cloaked, 4); // DWMWA_CLOAKED
          if (cloaked.value != 0) continue;
          _getPid(h, pidBuf);
          if (pidBuf.value == pid) continue;
          final buf = calloc<Uint16>(len + 2);
          String title;
          try {
            _getText(h, buf, len + 1);
            title = buf.cast<Utf16>().toDartString();
          } finally {
            calloc.free(buf);
          }
          if (title == 'Program Manager') continue;
          var exe = exeOf(pidBuf.value);
          if (exe.toLowerCase().endsWith('applicationframehost.exe')) exe = '';
          out.add(OpenWindow(h, title, exe));
        }
      } finally {
        calloc.free(pidBuf);
        calloc.free(cloaked);
      }
      return out;
    } catch (e) {
      debugPrint('OpenWindows.list failed: $e');
      return const [];
    }
  }

  /// Brings a window to the front (restoring it if it was minimized).
  void switchTo(int hwnd) {
    try {
      _init();
      if (_isIconic(hwnd) != 0) _showWindow(hwnd, 9);
      // A quick Alt tap lets Windows allow the focus change.
      _keybdEvent(0x12, 0, 0, 0);
      _keybdEvent(0x12, 0, 2, 0);
      _setForeground(hwnd);
    } catch (e) {
      debugPrint('OpenWindows.switchTo failed: $e');
    }
  }

  /// Process id that owns [hwnd] (0 if unknown).
  int pidOf(int hwnd) {
    try {
      _init();
      final b = calloc<Uint32>();
      try {
        _getPid(hwnd, b);
        return b.value;
      } finally {
        calloc.free(b);
      }
    } catch (_) {
      return 0;
    }
  }

  /// Process id of the window in front (0 if none).
  int foregroundPid() {
    try {
      _init();
      final h = _foreground();
      if (h == 0) return 0;
      final b = calloc<Uint32>();
      try {
        _getPid(h, b);
        return b.value;
      } finally {
        calloc.free(b);
      }
    } catch (_) {
      return 0;
    }
  }

  /// True when the window in front belongs to this app.
  bool foregroundIsSelf() => foregroundPid() == pid;

  /// Handle of the window in front (0 if none or if it is this app).
  int foregroundHwnd() {
    try {
      _init();
      if (foregroundIsSelf()) return 0;
      return _foreground();
    } catch (_) {
      return 0;
    }
  }

  /// Asks the program to close, like clicking its X.
  void close(int hwnd) {
    try {
      _init();
      _postMessage(hwnd, 0x0010, 0, 0);
    } catch (_) {}
  }
}
