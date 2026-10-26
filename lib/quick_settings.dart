import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'gamepad.dart';
import 'launcher.dart';
import 'sys_keys.dart';

/// Like the Windows Game Bar settings panel: quick toggles and shortcuts that
/// work with a controller. Pops a value the bar understands, or null.
class QuickSettingsDialog extends StatelessWidget {
  const QuickSettingsDialog({super.key});

  static Future<void> _page(BuildContext ctx, String page) async {
    try {
      await Process.run('cmd', ['/c', 'start', '', 'ms-settings:$page']);
    } catch (_) {}
    if (ctx.mounted) Navigator.pop(ctx, 'hide');
  }

  Widget _row(BuildContext ctx, IconData icon, String title, VoidCallback onTap,
      {String? sub, bool first = false, Widget? trailing}) {
    return ListTile(
      autofocus: first,
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontSize: 20)),
      subtitle: sub == null ? null : Text(sub, style: const TextStyle(fontSize: 14)),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = WindowsGamepadService.instance;
    return Dialog(
      child: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
              child: Row(children: [
                const Icon(Icons.tune_rounded),
                const SizedBox(width: 10),
                const Text('Quick settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _row(context, Icons.keyboard_rounded, 'Show keyboard', () {
                    Navigator.pop(context, 'keyboard');
                  }, first: true, trailing: const SizedBox.shrink()),
                  Focus(
                    onKeyEvent: (_, e) {
                      if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
                      if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
                        SysKeys.volumeDown();
                        return KeyEventResult.handled;
                      }
                      if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
                        SysKeys.volumeUp();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: _row(context, Icons.volume_up_rounded, 'Volume', SysKeys.mute,
                        sub: 'Left / Right to change, A to mute or unmute',
                        trailing: const Icon(Icons.swap_horiz_rounded)),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: pad.cursorMode,
                    builder: (_, on, __) => SwitchListTile(
                      secondary: const Icon(Icons.mouse_rounded),
                      value: on,
                      title: const Text('Gamepad cursor', style: TextStyle(fontSize: 20)),
                      subtitle: const Text(
                        'Left stick = mouse, A = click, B = right click, right stick = scroll (while another app is in front)',
                        style: TextStyle(fontSize: 14),
                      ),
                      onChanged: pad.setCursorMode,
                    ),
                  ),
                  _row(context, Icons.wifi_rounded, 'Network', () => _page(context, 'network')),
                  _row(context, Icons.bluetooth_rounded, 'Bluetooth & devices', () => _page(context, 'bluetooth')),
                  _row(context, Icons.airplanemode_active_rounded, 'Airplane mode', () => _page(context, 'network-airplanemode')),
                  _row(context, Icons.mic_rounded, 'Sound, speakers & microphone', () => _page(context, 'sound')),
                  _row(context, Icons.settings_applications_rounded, 'More Windows settings', () => _page(context, '')),
                  const Divider(),
                  _row(context, Icons.settings_rounded, 'Bar settings (button, hold time, freeze)',
                      () => Navigator.pop(context, 'settings')),
                  _row(context, Icons.bedtime_rounded, 'Sleep', () => Navigator.pop(context, 'sleep'), trailing: const SizedBox.shrink()),
                  _row(context, Icons.restart_alt_rounded, 'Restart', () => Navigator.pop(context, 'restart'), trailing: const SizedBox.shrink()),
                  _row(context, Icons.power_settings_new_rounded, 'Shut down', () => Navigator.pop(context, 'shutdown'), trailing: const SizedBox.shrink()),
                  _row(context, Icons.logout_rounded, 'Sign out', () => Navigator.pop(context, 'signout'), trailing: const SizedBox.shrink()),
                  _row(context, Icons.close_rounded, 'Close Everything Bar', () => Navigator.pop(context, 'exit'), trailing: const SizedBox.shrink()),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
