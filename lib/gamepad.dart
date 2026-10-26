import 'dart:async';
import 'dart:ffi';
import 'dart:io' show Platform, pid;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'settings.dart';

/// Lets an Xbox-style controller (XInput) and ordinary HTPC remotes drive the
/// home screen on Windows, exactly like a TV remote on an Android box.
///
/// The controller is turned into plain keyboard presses (arrows, Enter,
/// Escape, Page Up/Down, Play/Pause), so every screen that already works with
/// a TV remote works with a controller. Keys are only sent while the Home Shell
/// window is the active window — a game or another app in front is never
/// touched.
///
///   D-pad / left stick  arrows          A  Enter (OK)
///   B / Back (View)     Escape (back)   Start  Play/Pause
///   LB / RB             Page Up / Down (previous / next channel)
class WindowsGamepadService {
  WindowsGamepadService._();
  static final WindowsGamepadService instance = WindowsGamepadService._();

  // XInput button bits.
  static const int _dpadUp = 0x0001;
  static const int _dpadDown = 0x0002;
  static const int _dpadLeft = 0x0004;
  static const int _dpadRight = 0x0008;
  static const int _start = 0x0010;
  static const int _back = 0x0020;
  static const int _lb = 0x0100;
  static const int _rb = 0x0200;
  static const int _a = 0x1000;
  static const int _b = 0x2000;
  static const int _x = 0x4000;
  static const int _y = 0x8000;

  // Windows virtual-key codes.
  static const int _vkReturn = 0x0D;
  static const int _vkEscape = 0x1B;
  static const int _vkPageUp = 0x21;
  static const int _vkPageDown = 0x22;
  static const int _vkLeft = 0x25;
  static const int _vkUp = 0x26;
  static const int _vkRight = 0x27;
  static const int _vkDown = 0x28;
  static const int _vkPlayPause = 0xB3;
  static const int _vkF2 = 0x71; // X / Square: edit or close
  static const int _vkF3 = 0x72; // Y / Triangle: add

  static const int _keyEventExtended = 0x0001;
  static const int _keyEventKeyUp = 0x0002;

  // Keys that need the "extended key" flag to be read as the navigation keys.
  static const Set<int> _extendedKeys = {
    _vkPageUp,
    _vkPageDown,
    _vkLeft,
    _vkUp,
    _vkRight,
    _vkDown,
    _vkPlayPause,
  };

  bool _started = false;
  Timer? _timer;

  /// The Xbox/Guide button (the big logo button). Windows hides it from the
  /// normal XInput call, so it is read through the undocumented XInputGetStateEx.
  static const int _guide = 0x0400;
  int Function(int, Pointer<Uint8>)? _getStateEx;
  Pointer<Uint8>? _exState;

  /// Called when the Home gesture is used while another app is in front.
  void Function()? onHomeRequested;
  Pointer<Uint8>? _state;
  int _lastScan = 0;
  List<int> _connected = const [];

  /// Other (non-Xbox) controllers, read through the older Windows joystick
  /// API: PlayStation pads, generic USB pads, GameSir in DirectInput mode.
  List<int> _joyConnected = const [];
  Pointer<Uint8>? _joyInfo;
  Pointer<Uint8>? _joyCaps;
  bool _joyOk = false;
  final Map<int, _PadKind> _joyKinds = <int, _PadKind>{};

  /// Name of the controller last seen driving the app, e.g. "Xbox controller"
  /// or "PlayStation controller". Null when none is connected.
  final ValueNotifier<String?> controllerName = ValueNotifier<String?>(null);

  final Set<int> _held = <int>{};

  /// Left stick moves the mouse, A / B click, right stick scrolls — used while
  /// another app is in front. Off at every start.
  final ValueNotifier<bool> cursorMode = ValueNotifier<bool>(false);
  void Function(int, int, int, int, int)? _mouseEvent;
  bool _cursorLeftDown = false;
  bool _cursorRightDown = false;
  Pointer<Uint32>? _pidOut;
  bool _activeNow = false;
  int _frame = 0;

  void setCursorMode(bool on) {
    cursorMode.value = on;
    if (!on) _releaseCursorButtons();
  }

  void _releaseCursorButtons() {
    final m = _mouseEvent;
    if (m == null) return;
    if (_cursorLeftDown) m(0x0004, 0, 0, 0, 0);
    if (_cursorRightDown) m(0x0010, 0, 0, 0, 0);
    _cursorLeftDown = false;
    _cursorRightDown = false;
  }

  void _cursorTick() {
    final m = _mouseEvent;
    if (m == null || _connected.isEmpty) return;
    if (_getState(_connected.first, _state!) != 0) return;
    final d = ByteData.sublistView(_state!.asTypedList(16));
    final b = d.getUint16(4, Endian.little);
    double axis(int v) {
      const dead = 7849;
      if (v.abs() < dead) return 0;
      final n = (v.abs() - dead) / (32767 - dead);
      return (v < 0 ? -1 : 1) * n * n;
    }

    final dx = (axis(d.getInt16(8, Endian.little)) * 22).round();
    final dy = (-axis(d.getInt16(10, Endian.little)) * 22).round();
    if (dx != 0 || dy != 0) m(0x0001, dx, dy, 0, 0);
    final wheel = (axis(d.getInt16(14, Endian.little)) * 90).round();
    if (wheel != 0) m(0x0800, 0, 0, wheel, 0);
    final a = b & _a != 0;
    if (a && !_cursorLeftDown) m(0x0002, 0, 0, 0, 0);
    if (!a && _cursorLeftDown) m(0x0004, 0, 0, 0, 0);
    _cursorLeftDown = a;
    final r = b & _b != 0;
    if (r && !_cursorRightDown) m(0x0008, 0, 0, 0, 0);
    if (!r && _cursorRightDown) m(0x0010, 0, 0, 0, 0);
    _cursorRightDown = r;
  }

  /// Waits until every controller button is let go (up to [max]), plus a short
  /// pause. Used before waking or opening another app, so the button you just
  /// pressed on the bar is not seen by that app.
  Future<void> waitForRelease({Duration max = const Duration(milliseconds: 1500)}) async {
    if (!_started) return;
    final end = _clock.elapsedMilliseconds + max.inMilliseconds;
    while (_clock.elapsedMilliseconds < end) {
      var down = false;
      for (final i in _connected) {
        if (_padButtons(i) & 0xF3FF != 0) down = true;
      }
      for (final id in _joyConnected) {
        if (_joyButtons(id) != 0) down = true;
      }
      if (!down) break;
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  final Map<int, int> _nextRepeatMs = <int, int>{};
  final Stopwatch _clock = Stopwatch()..start();

  late final int Function(int, Pointer<Uint8>) _getState;
  late final void Function(int, int, int, int) _keybdEvent;
  late final int Function() _foregroundWindow;
  late final int Function(int, Pointer<Uint32>) _windowProcessId;
  late final int Function(int, Pointer<Uint8>) _joyGetPosEx;
  late final int Function(int, Pointer<Uint8>, int) _joyGetDevCaps;

  /// Starts polling. Safe to call more than once; does nothing off Windows or
  /// when XInput can't be loaded.
  void start() {
    if (_started || kIsWeb || !Platform.isWindows) return;
    try {
      final xinput = _openXInput();
      _getState = xinput
          .lookup<NativeFunction<Uint32 Function(Uint32, Pointer<Uint8>)>>(
            'XInputGetState',
          )
          .asFunction();
      final user32 = DynamicLibrary.open('user32.dll');
      _keybdEvent = user32
          .lookup<NativeFunction<Void Function(Uint8, Uint8, Uint32, IntPtr)>>(
            'keybd_event',
          )
          .asFunction();
      _foregroundWindow = user32
          .lookup<NativeFunction<IntPtr Function()>>('GetForegroundWindow')
          .asFunction();
      _windowProcessId = user32
          .lookup<NativeFunction<Uint32 Function(IntPtr, Pointer<Uint32>)>>(
            'GetWindowThreadProcessId',
          )
          .asFunction();
      _state = calloc<Uint8>(16);
      _exState = calloc<Uint8>(16);
      _pidOut = calloc<Uint32>();
      try {
        _mouseEvent = user32
            .lookup<NativeFunction<Void Function(Uint32, Int32, Int32, Int32, IntPtr)>>(
              'mouse_event',
            )
            .asFunction();
      } catch (_) {}
      _asyncKey = user32
          .lookup<NativeFunction<Int16 Function(Int32)>>('GetAsyncKeyState')
          .asFunction();
      try {
        final kernel = DynamicLibrary.open('kernel32.dll');
        final loadLib = kernel
            .lookup<NativeFunction<IntPtr Function(Pointer<Utf8>)>>('LoadLibraryA')
            .asFunction<int Function(Pointer<Utf8>)>();
        final getProc = kernel
            .lookup<NativeFunction<IntPtr Function(IntPtr, IntPtr)>>('GetProcAddress')
            .asFunction<int Function(int, int)>();
        for (final name in const ['xinput1_4.dll', 'xinput1_3.dll']) {
          final n = name.toNativeUtf8();
          final h = loadLib(n);
          calloc.free(n);
          if (h == 0) continue;
          final addr = getProc(h, 100); // ordinal 100 = XInputGetStateEx
          if (addr != 0) {
            _getStateEx = Pointer<
              NativeFunction<Uint32 Function(Uint32, Pointer<Uint8>)>
            >.fromAddress(addr).asFunction();
            break;
          }
        }
      } catch (e) {
        debugPrint('Guide button unavailable ($e)');
      }
      try {
        final winmm = DynamicLibrary.open('winmm.dll');
        _joyGetPosEx = winmm
            .lookup<NativeFunction<Uint32 Function(Uint32, Pointer<Uint8>)>>(
              'joyGetPosEx',
            )
            .asFunction();
        _joyGetDevCaps = winmm
            .lookup<
              NativeFunction<Uint32 Function(IntPtr, Pointer<Uint8>, Uint32)>
            >('joyGetDevCapsW')
            .asFunction();
        _joyInfo = calloc<Uint8>(52);
        _joyCaps = calloc<Uint8>(1024);
        _joyOk = true;
      } catch (e) {
        debugPrint('WindowsGamepadService: joystick API unavailable ($e)');
      }
    } catch (e) {
      debugPrint('WindowsGamepadService: unavailable ($e)');
      return;
    }
    _started = true;
    // HTPC remotes: the "Back" button arrives as Browser Back. The app's
    // screens listen for Escape, so turn one into the other.
    HardwareKeyboard.instance.addHandler(_onKey);
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  DynamicLibrary _openXInput() {
    for (final name in const [
      'xinput1_4.dll',
      'xinput1_3.dll',
      'xinput9_1_0.dll',
    ]) {
      try {
        return DynamicLibrary.open(name);
      } catch (_) {}
    }
    throw StateError('XInput not found');
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.browserBack) {
      _tap(_vkEscape);
      return true;
    }
    return false;
  }

  int _trigSince = -1;
  bool _trigFired = false;
  bool _hotkeyWasDown = false;
  int Function(int)? _asyncKey;

  // ---- shortcut recording ---------------------------------------------------
  Completer<ShellShortcut?>? _recording;
  int _recDeadline = 0;
  bool _recStarted = false;
  bool _recArmed = false; // waits until everything is let go first
  ShellShortcut _recPeak = const ShellShortcut();
  int _recPeakCount = 0;

  static int _bits(int v) {
    var n = 0;
    while (v != 0) {
      n += v & 1;
      v >>= 1;
    }
    return n;
  }

  static const Set<int> _skipKeys = {0x01, 0x02, 0x04, 0x05, 0x06, 0x10, 0x11, 0x12};

  int _padButtons(int index) {
    final ex = _getStateEx;
    final ok = ex != null ? ex(index, _exState!) : _getState(index, _exState!);
    if (ok != 0) return 0;
    return ByteData.sublistView(_exState!.asTypedList(16)).getUint16(4, Endian.little);
  }

  int _joyButtons(int id) {
    if (!_joyOk) return 0;
    final info = _joyInfo!;
    info.asTypedList(52).fillRange(0, 52, 0);
    final data = ByteData.sublistView(info.asTypedList(52));
    data.setUint32(0, 52, Endian.little);
    data.setUint32(4, 0xFF, Endian.little);
    if (_joyGetPosEx(id, info) != 0) return 0;
    return data.getUint32(32, Endian.little);
  }

  List<int> _downKeys() {
    final key = _asyncKey;
    if (key == null) return const [];
    return [
      for (var vk = 8; vk < 255; vk++)
        if (!_skipKeys.contains(vk) && key(vk) & 0x8000 != 0) vk,
    ];
  }

  bool _matches(ShellShortcut sc) {
    if (sc.padMask != 0) {
      for (final i in _connected) {
        if (_padButtons(i) & sc.padMask == sc.padMask) return true;
      }
    }
    if (sc.joyMask != 0) {
      for (final id in _joyConnected) {
        if (_joyButtons(id) & sc.joyMask == sc.joyMask) return true;
      }
    }
    if (sc.keys.isNotEmpty) {
      final key = _asyncKey;
      if (key != null && sc.keys.every((vk) => key(vk) & 0x8000 != 0)) return true;
    }
    return false;
  }

  /// Listens for the next button press (one or several buttons held together,
  /// on a controller, a PlayStation/generic pad, a keyboard or a remote) and
  /// returns it when everything is let go. Null if nothing is pressed in time.
  Future<ShellShortcut?> record({Duration timeout = const Duration(seconds: 20)}) {
    _recording?.complete(null);
    final c = Completer<ShellShortcut?>();
    _recording = c;
    _recStarted = false;
    _recArmed = false;
    _recPeak = const ShellShortcut();
    _recPeakCount = 0;
    _recDeadline = _clock.elapsedMilliseconds + timeout.inMilliseconds;
    return c.future;
  }

  void cancelRecording() {
    _recording?.complete(null);
    _recording = null;
  }

  void _recordTick() {
    final nowMs = _clock.elapsedMilliseconds;
    var pad = 0;
    for (final i in _connected) {
      final b = _padButtons(i);
      if (_bits(b) > _bits(pad)) pad = b;
    }
    var joy = 0;
    for (final id in _joyConnected) {
      final b = _joyButtons(id);
      if (_bits(b) > _bits(joy)) joy = b;
    }
    final keys = _downKeys();
    final count = _bits(pad) + _bits(joy) + keys.length;
    if (!_recArmed) {
      if (count == 0) {
        _recArmed = true;
        _recDeadline = nowMs + 20000;
      }
      return;
    }
    if (count > 0) {
      _recStarted = true;
      if (count >= _recPeakCount) {
        _recPeakCount = count;
        _recPeak = ShellShortcut(padMask: pad, joyMask: joy, keys: keys);
      }
    } else if (_recStarted) {
      final c = _recording;
      _recording = null;
      c?.complete(_recPeak);
      return;
    }
    if (nowMs > _recDeadline && !_recStarted) {
      final c = _recording;
      _recording = null;
      c?.complete(null);
    }
  }

  /// "Home" gesture: hold the saved shortcut (default: Guide for 1 second) or
  /// press Ctrl+Alt+H from any app to bring the bar up. Nothing is closed, and
  /// a quick tap of the same button still goes to the other app untouched,
  /// because this only watches the buttons.
  void _checkGuide() {
    if (_recording != null) {
      _recordTick();
      return;
    }
    final nowMs = _clock.elapsedMilliseconds;
    var wantHome = false;
    final settings = ShellSettings.instance;

    if (_matches(settings.shortcut)) {
      if (_trigSince < 0) _trigSince = nowMs;
      if (!_trigFired && nowMs - _trigSince >= settings.holdMs) {
        _trigFired = true;
        wantHome = true;
      }
    } else {
      _trigSince = -1;
      _trigFired = false;
    }

    final key = _asyncKey;
    if (key != null) {
      final combo = key(0x11) & 0x8000 != 0 &&
          key(0x12) & 0x8000 != 0 &&
          key(0x48) & 0x8000 != 0;
      if (combo && !_hotkeyWasDown) wantHome = true;
      _hotkeyWasDown = combo;
    }

    if (wantHome && !_appIsActive) onHomeRequested?.call();
  }

  bool get _appIsActive => _activeNow;

  bool _computeActive() {
    final hwnd = _foregroundWindow();
    if (hwnd == 0) return false;
    final out = _pidOut!;
    _windowProcessId(hwnd, out);
    return out.value == pid;
  }

  void _sendKey(int vk, {required bool down}) {
    var flags = _extendedKeys.contains(vk) ? _keyEventExtended : 0;
    if (!down) flags |= _keyEventKeyUp;
    _keybdEvent(vk, 0, flags, 0);
  }

  void _tap(int vk) {
    _sendKey(vk, down: true);
    _sendKey(vk, down: false);
  }

  void _releaseAll() {
    for (final vk in _held) {
      _sendKey(vk, down: false);
    }
    _held.clear();
    _nextRepeatMs.clear();
  }

  void _tick() {
    _activeNow = _computeActive();
    // Idle (another app in front, nothing to do): wake only every third frame
    // to keep CPU use close to zero. Full speed while the bar is in front.
    if (!_activeNow &&
        !cursorMode.value &&
        _recording == null &&
        _held.isEmpty &&
        (++_frame % 3 != 0)) {
      return;
    }
    final nowMs = _clock.elapsedMilliseconds;

    // Look for connected controllers about once a second; polling an empty
    // slot every frame is wasteful.
    if (nowMs - _lastScan > 1000) {
      _lastScan = nowMs;
      _connected = [
        for (var i = 0; i < 4; i++)
          if (_getState(i, _state!) == 0) i,
      ];
    }

    if (_joyOk && nowMs - _lastJoyScan > 1000) {
      _lastJoyScan = nowMs;
      _scanJoysticks();
    }

    _checkGuide();
    if (cursorMode.value && !_activeNow) _cursorTick();

    final wanted = <int>{};
    if (_connected.isEmpty && _joyConnected.isNotEmpty && _appIsActive) {
      for (final id in _joyConnected) {
        _readJoystick(id, wanted);
      }
    }
    if (_connected.isNotEmpty && _appIsActive) {
      for (final index in _connected) {
        if (_getState(index, _state!) != 0) continue;
        final data = ByteData.sublistView(_state!.asTypedList(16));
        final buttons = data.getUint16(4, Endian.little);
        final lx = data.getInt16(8, Endian.little);
        final ly = data.getInt16(10, Endian.little);
        const stick = 16000;
        if (buttons & _dpadUp != 0 || ly > stick) wanted.add(_vkUp);
        if (buttons & _dpadDown != 0 || ly < -stick) wanted.add(_vkDown);
        if (buttons & _dpadLeft != 0 || lx < -stick) wanted.add(_vkLeft);
        if (buttons & _dpadRight != 0 || lx > stick) wanted.add(_vkRight);
        if (buttons & _a != 0) wanted.add(_vkReturn);
        if (buttons & (_b | _back) != 0) wanted.add(_vkEscape);
        if (buttons & _start != 0) wanted.add(_vkPlayPause);
        if (buttons & _x != 0) wanted.add(_vkF2);
        if (buttons & _y != 0) wanted.add(_vkF3);
        if (buttons & _lb != 0) wanted.add(_vkPageUp);
        if (buttons & _rb != 0) wanted.add(_vkPageDown);
      }
    }
    if (_connected.isNotEmpty) {
      controllerName.value = 'Xbox controller';
    } else if (_joyConnected.isNotEmpty) {
      controllerName.value = _joyKinds[_joyConnected.first]?.label;
    } else {
      controllerName.value = null;
    }

    if (_recording != null) wanted.clear();

    // Released keys.
    for (final vk in _held.difference(wanted).toList()) {
      _sendKey(vk, down: false);
      _held.remove(vk);
      _nextRepeatMs.remove(vk);
    }
    // New presses, then held-key repeats (like a keyboard's typematic repeat).
    for (final vk in wanted) {
      if (_held.add(vk)) {
        _sendKey(vk, down: true);
        _nextRepeatMs[vk] = nowMs + (_isNavigation(vk) ? 350 : 500);
      } else if (nowMs >= (_nextRepeatMs[vk] ?? nowMs + 1)) {
        _sendKey(vk, down: true);
        _nextRepeatMs[vk] = nowMs + (_isNavigation(vk) ? 90 : 40);
      }
    }
    if (_connected.isEmpty && _joyConnected.isEmpty && _held.isNotEmpty) {
      _releaseAll();
    }
  }

  int _lastJoyScan = 0;

  void _scanJoysticks() {
    final found = <int>[];
    final info = _joyInfo!;
    for (var id = 0; id < 16; id++) {
      info.asTypedList(52).fillRange(0, 52, 0);
      ByteData.sublistView(info.asTypedList(52)).setUint32(0, 52, Endian.little);
      ByteData.sublistView(info.asTypedList(52)).setUint32(4, 0xFF, Endian.little);
      if (_joyGetPosEx(id, info) != 0) continue;
      found.add(id);
      _joyKinds.putIfAbsent(id, () => _identify(id));
    }
    _joyKinds.removeWhere((id, _) => !found.contains(id));
    _joyConnected = found;
  }

  _PadKind _identify(int id) {
    try {
      final caps = _joyCaps!;
      if (_joyGetDevCaps(id, caps, 728) != 0) return _PadKind.generic;
      final vendor = ByteData.sublistView(caps.asTypedList(8)).getUint16(
        0,
        Endian.little,
      );
      final nameBytes = caps.asTypedList(68).sublist(4, 68);
      final name = String.fromCharCodes(
        Uint16List.view(Uint8List.fromList(nameBytes).buffer),
      ).split('\u0000').first.toLowerCase();
      if (vendor == 0x054C ||
          name.contains('dualsense') ||
          name.contains('dualshock') ||
          name.contains('wireless controller')) {
        return _PadKind.playstation;
      }
    } catch (_) {}
    return _PadKind.generic;
  }

  /// Reads one non-Xbox controller and adds the keys it is pressing.
  void _readJoystick(int id, Set<int> wanted) {
    final info = _joyInfo!;
    info.asTypedList(52).fillRange(0, 52, 0);
    final data = ByteData.sublistView(info.asTypedList(52));
    data.setUint32(0, 52, Endian.little);
    data.setUint32(4, 0xFF, Endian.little);
    if (_joyGetPosEx(id, info) != 0) return;
    final x = data.getUint32(8, Endian.little);
    final y = data.getUint32(12, Endian.little);
    final buttons = data.getUint32(32, Endian.little);
    final pov = data.getUint32(40, Endian.little) & 0xFFFF;
    const low = 32768 - 16000;
    const high = 32768 + 16000;
    if (y < low) wanted.add(_vkUp);
    if (y > high) wanted.add(_vkDown);
    if (x < low) wanted.add(_vkLeft);
    if (x > high) wanted.add(_vkRight);
    if (pov != 0xFFFF) {
      if (pov >= 31500 || pov <= 4500) wanted.add(_vkUp);
      if (pov >= 4500 && pov <= 13500) wanted.add(_vkRight);
      if (pov >= 13500 && pov <= 22500) wanted.add(_vkDown);
      if (pov >= 22500 && pov <= 31500) wanted.add(_vkLeft);
    }
    bool pressed(int n) => buttons & (1 << n) != 0;
    final kind = _joyKinds[id] ?? _PadKind.generic;
    if (kind == _PadKind.playstation) {
      // Windows numbers a PlayStation pad: 0 Square, 1 Cross, 2 Circle,
      // 3 Triangle, 4 L1, 5 R1, 8 Share, 9 Options.
      if (pressed(1)) wanted.add(_vkReturn); // Cross = OK
      if (pressed(2) || pressed(8)) wanted.add(_vkEscape); // Circle = back
      if (pressed(9)) wanted.add(_vkPlayPause); // Options
      if (pressed(0)) wanted.add(_vkF2); // Square
      if (pressed(3)) wanted.add(_vkF3); // Triangle
      if (pressed(4)) wanted.add(_vkPageUp);
      if (pressed(5)) wanted.add(_vkPageDown);
    } else {
      // Generic pad (Xbox-style order): 0 A, 1 B, 4 LB, 5 RB, 6 Back, 7 Start.
      if (pressed(0)) wanted.add(_vkReturn);
      if (pressed(1) || pressed(6)) wanted.add(_vkEscape);
      if (pressed(7)) wanted.add(_vkPlayPause);
      if (pressed(2)) wanted.add(_vkF2);
      if (pressed(3)) wanted.add(_vkF3);
      if (pressed(4)) wanted.add(_vkPageUp);
      if (pressed(5)) wanted.add(_vkPageDown);
    }
  }

  bool _isNavigation(int vk) =>
      vk == _vkUp ||
      vk == _vkDown ||
      vk == _vkLeft ||
      vk == _vkRight ||
      vk == _vkPageUp ||
      vk == _vkPageDown;
}

enum _PadKind {
  generic('Game controller'),
  playstation('PlayStation controller');

  const _PadKind(this.label);
  final String label;
}
