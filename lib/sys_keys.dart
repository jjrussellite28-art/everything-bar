import 'dart:ffi';
import 'dart:io' show Platform;

/// Sends a few media keys (volume) the same way a keyboard's volume buttons do.
class SysKeys {
  static void Function(int, int, int, int)? _kb;

  static void _tap(int vk) {
    if (!Platform.isWindows) return;
    try {
      _kb ??= DynamicLibrary.open('user32.dll')
          .lookupFunction<Void Function(Uint8, Uint8, Uint32, IntPtr), void Function(int, int, int, int)>(
            'keybd_event',
          );
      _kb!(vk, 0, 0, 0);
      _kb!(vk, 0, 2, 0);
    } catch (_) {}
  }

  /// Each press is about 2% of the volume.
  static void volumeUp() => _tap(0xAF);
  static void volumeDown() => _tap(0xAE);
  static void mute() => _tap(0xAD);
}
