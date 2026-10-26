import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Alignment;
import 'package:window_manager/window_manager.dart';

import 'freezer.dart';
import 'gamepad.dart';
import 'open_windows.dart';
import 'settings.dart';

/// Controls the small bar window: where it sits, when it shows and hides, and
/// the temporary bigger window used for the Add/Edit and Power dialogs.
class ShellMode {
  ShellMode._();
  static final ShellMode instance = ShellMode._();

  /// Goes up by one each time the bar is asked for (hold Guide, Ctrl+Alt+H).
  final ValueNotifier<int> barRequest = ValueNotifier<int>(0);

  bool visible = false;

  /// The window that was in front when the bar was opened.
  int _previousHwnd = 0;

  /// [freeze] pauses the app in front (if the setting is on) so it doesn't keep
  /// running or reacting behind the bar. It is resumed by [hide].
  void showBar({bool freeze = true}) {
    _previousHwnd = freeze ? OpenWindows.instance.foregroundHwnd() : 0;
    if (freeze && ShellSettings.instance.freeze) {
      Freezer.instance.freezeForeground();
    }
    barRequest.value++;
  }

  double _widthFor(int itemCount) {
    final display = ui.PlatformDispatcher.instance.displays.first;
    final screenW = display.size.width / display.devicePixelRatio;
    return (itemCount * 70.0 + 64).clamp(320.0, screenW - 60.0);
  }

  /// Puts the bar at the top of the screen. [slim] = icons only (used while
  /// another app is in front), [focus] = take the keyboard/controller focus.
  Future<void> applyBar({required int itemCount, bool slim = false, bool focus = true}) async {
    await windowManager.setFullScreen(false);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSize(ui.Size(_widthFor(itemCount), slim ? 84 : 156));
    await windowManager.setAlignment(Alignment.topCenter);
    await windowManager.show();
    if (focus) await windowManager.focus();
    visible = true;
  }

  /// Only changes the size (no focus change) — slim while another app is used.
  Future<void> resizeBar({required int itemCount, required bool slim}) async {
    await windowManager.setSize(ui.Size(_widthFor(itemCount), slim ? 84 : 156));
    await windowManager.setAlignment(Alignment.topCenter);
  }

  /// B / Esc: give control back to the app that was in front. When the bar is
  /// kept on screen it stays; otherwise it hides.
  Future<void> leave() async {
    // Let go of the button first, or the app wakes up and sees it still held.
    await WindowsGamepadService.instance.waitForRelease();
    Freezer.instance.thawCurrent();
    if (ShellSettings.instance.pinned) {
      if (_previousHwnd != 0) OpenWindows.instance.switchTo(_previousHwnd);
    } else {
      await hide(resumePrevious: true);
    }
  }

  /// Switches to another open window. The target is resumed first (and only
  /// after the controller buttons are released), then brought to the front.
  Future<void> goTo(int hwnd) async {
    await WindowsGamepadService.instance.waitForRelease();
    Freezer.instance.thawWindow(hwnd);
    OpenWindows.instance.switchTo(hwnd);
    await hide();
  }

  /// Hides the bar. The app you were in stays paused when you went somewhere
  /// else (if "keep paused" is on); [resumePrevious] wakes it up.
  Future<void> hide({bool resumePrevious = false}) async {
    if (!ShellSettings.instance.keepFrozen) {
      Freezer.instance.thawAll();
    } else if (resumePrevious) {
      Freezer.instance.thawCurrent();
    }
    if (ShellSettings.instance.pinned) return; // stays on screen
    visible = false;
    await windowManager.hide();
  }

  /// A roomy window for dialogs; call [applyBar] afterwards to shrink back.
  Future<void> enterBig() async {
    await windowManager.setSize(const ui.Size(780, 640));
    await windowManager.setAlignment(Alignment.center);
    await windowManager.show();
    await windowManager.focus();
  }
}
