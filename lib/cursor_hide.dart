import 'dart:async';
import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:window_manager/window_manager.dart';

/// Hides the mouse pointer while the app is full screen and the mouse has not
/// moved for a few seconds (couch / controller use). Any mouse movement or
/// click brings it straight back.
class CursorAutoHide {
  CursorAutoHide._();
  static final CursorAutoHide instance = CursorAutoHide._();

  static const Duration _idle = Duration(seconds: 3);

  bool _started = false;
  bool _enabled = true;
  bool _hidden = false;
  Timer? _timer;
  late final int Function(int) _showCursor;

  void start({bool enabled = true}) {
    _enabled = enabled;
    if (_started || kIsWeb || !Platform.isWindows) return;
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      _showCursor = user32
          .lookup<NativeFunction<Int32 Function(Int32)>>('ShowCursor')
          .asFunction();
    } catch (e) {
      debugPrint('CursorAutoHide: unavailable ($e)');
      return;
    }
    _started = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    _restartTimer();
  }

  /// Turns the auto-hide on or off (Settings). Turning it off shows the pointer.
  void setEnabled(bool value) {
    _enabled = value;
    if (!value) {
      _timer?.cancel();
      _show();
    } else if (_started) {
      _restartTimer();
    }
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerHoverEvent ||
        event is PointerMoveEvent ||
        event is PointerDownEvent ||
        event is PointerScrollEvent) {
      _show();
      _restartTimer();
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer(_idle, _hide);
  }

  Future<void> _hide() async {
    if (_hidden || !_enabled) return;
    try {
      if (!await windowManager.isFullScreen()) {
        _restartTimer();
        return;
      }
    } catch (_) {
      return;
    }
    _showCursor(0);
    _hidden = true;
  }

  void _show() {
    if (!_hidden) return;
    _hidden = false;
    // Undo the hide completely, however many times it was counted.
    for (var i = 0; i < 10; i++) {
      if (_showCursor(1) >= 0) break;
    }
  }
}
