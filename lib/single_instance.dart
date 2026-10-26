import 'dart:ffi';
import 'dart:io' show Platform, pid;

import 'package:ffi/ffi.dart';

/// Makes sure only one Everything Bar runs. A second start just brings the
/// first one forward and quits.
class SingleInstance {
  static const _name = r'Local\EverythingBar.SingleInstance';
  static int _held = 0;

  /// True when this is the only copy (and claims it); false if one is running.
  static bool acquire() {
    if (!Platform.isWindows) return true;
    try {
      final k = DynamicLibrary.open('kernel32.dll');
      final open = k.lookupFunction<
        IntPtr Function(Uint32, Int32, Pointer<Utf16>),
        int Function(int, int, Pointer<Utf16>)
      >('OpenMutexW');
      final create = k.lookupFunction<
        IntPtr Function(Pointer<Void>, Int32, Pointer<Utf16>),
        int Function(Pointer<Void>, int, Pointer<Utf16>)
      >('CreateMutexW');
      final n = _name.toNativeUtf16();
      try {
        if (open(0x00100000, 0, n) != 0) return false; // SYNCHRONIZE: already there
        _held = create(nullptr, 0, n); // kept until this process ends
      } finally {
        calloc.free(n);
      }
    } catch (_) {}
    return true;
  }

  /// Shows the window of the copy that is already running.
  static void showExisting() {
    if (!Platform.isWindows) return;
    try {
      final u = DynamicLibrary.open('user32.dll');
      final findEx = u.lookupFunction<
        IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>),
        int Function(int, int, Pointer<Utf16>, Pointer<Utf16>)
      >('FindWindowExW');
      final getPid = u.lookupFunction<
        Uint32 Function(IntPtr, Pointer<Uint32>),
        int Function(int, Pointer<Uint32>)
      >('GetWindowThreadProcessId');
      final show = u.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('ShowWindow');
      final front = u.lookupFunction<Int32 Function(IntPtr), int Function(int)>('SetForegroundWindow');
      final cls = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
      final out = calloc<Uint32>();
      try {
        var h = 0;
        while (true) {
          h = findEx(0, h, cls, nullptr);
          if (h == 0) break;
          getPid(h, out);
          if (out.value != pid) {
            show(h, 5); // SW_SHOW
            front(h);
            break;
          }
        }
      } finally {
        calloc.free(cls);
        calloc.free(out);
      }
    } catch (_) {}
  }
}
