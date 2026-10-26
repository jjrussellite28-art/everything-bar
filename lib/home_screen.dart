import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'icon_cache.dart';
import 'launcher.dart';
import 'open_windows.dart';
import 'quick_settings.dart';
import 'autostart.dart';
import 'freezer.dart';
import 'gamepad.dart';
import 'settings.dart';
import 'shell_mode.dart';
import 'tiles.dart';

/// The whole app: one small bar that floats on top of whatever you are doing.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WindowListener {
  List<ShellTile> _tiles = [];
  List<OpenWindow> _open = [];
  final Map<String, File?> _icons = {};
  final Set<String> _iconRequested = {};
  final ValueNotifier<String> _label = ValueNotifier<String>('');
  Timer? _timer;
  bool _busyDialog = false;
  bool _slim = false;

  static const _idleHint = 'Pick an app     Your bar button brings this back into focus';

  @override
  void initState() {
    super.initState();
    _label.value = _idleHint;
    windowManager.addListener(this);
    ShellMode.instance.barRequest.addListener(_applyBar);
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (ShellMode.instance.visible && !_busyDialog) _refreshWindows();
    });
    TileStore.load().then((t) {
      if (!mounted) return;
      setState(() => _tiles = t);
      ShellMode.instance.showBar(freeze: false);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    ShellMode.instance.barRequest.removeListener(_applyBar);
    Freezer.instance.thawAll();
    _timer?.cancel();
    super.dispose();
  }

  // ---- data ---------------------------------------------------------------

  @override
  void onWindowBlur() {
    if (!ShellSettings.instance.pinned || _busyDialog || !mounted) return;
    setState(() => _slim = true);
    ShellMode.instance.resizeBar(itemCount: _barItemCount, slim: true);
  }

  @override
  void onWindowFocus() {
    if (!mounted || !_slim) return;
    setState(() => _slim = false);
    ShellMode.instance.resizeBar(itemCount: _barItemCount, slim: false);
  }

  void _refreshWindows() {
    if (!mounted) return;
    final list = OpenWindows.instance.list();
    final same = list.length == _open.length &&
        [
          for (var i = 0; i < list.length; i++)
            list[i].hwnd == _open[i].hwnd && list[i].title == _open[i].title,
        ].every((e) => e);
    if (same) return;
    final before = _barItemCount;
    setState(() => _open = list);
    if (_barItemCount != before) {
      ShellMode.instance.applyBar(itemCount: _barItemCount, slim: _slim, focus: false);
    }
  }

  int get _barItemCount => _open.length + _tiles.length + 3;

  Future<void> _applyBar() async {
    if (!mounted) return;
    _refreshWindows();
    setState(() => _slim = false);
    await ShellMode.instance.applyBar(itemCount: _barItemCount);
  }

  Future<void> _save() => TileStore.save(_tiles);

  /// Real icon for an .exe (made once, then kept), or null while loading.
  File? _iconFor(String exe) {
    if (exe.isEmpty) return null;
    if (_iconRequested.add(exe)) {
      IconCache.instance.iconFor(exe).then((f) {
        if (mounted) setState(() => _icons[exe] = f);
      });
    }
    return _icons[exe];
  }

  String _tileExe(ShellTile t) {
    if (t.kind != 'app') return '';
    final p = Launcher.expand(t.target.trim());
    final low = p.toLowerCase();
    return (low.endsWith('.exe') || low.endsWith('.lnk')) && File(p).existsSync() ? p : '';
  }

  // ---- actions --------------------------------------------------------------

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text, maxLines: 2)));
  }

  void _switchTo(OpenWindow w) {
    ShellMode.instance.goTo(w.hwnd);
  }

  void _closeWindow(OpenWindow w) {
    OpenWindows.instance.close(w.hwnd);
    Future.delayed(const Duration(milliseconds: 700), _refreshWindows);
  }

  Future<void> _launch(ShellTile t) async {
    await WindowsGamepadService.instance.waitForRelease();
    final err = await Launcher.open(t);
    if (err == null) {
      ShellMode.instance.hide();
    } else if (mounted) {
      _toast(err);
    }
  }

  /// Runs [body] in a bigger window (for dialogs), then shrinks back.
  Future<T?> _inBigWindow<T>(Future<T?> Function() body) async {
    _busyDialog = true;
    await ShellMode.instance.enterBig();
    try {
      return await body();
    } finally {
      _busyDialog = false;
      if (mounted) await ShellMode.instance.applyBar(itemCount: _barItemCount);
    }
  }

  Future<void> _edit(ShellTile? existing) async {
    final result = await _inBigWindow<_EditResult>(
      () => showDialog<_EditResult>(
        context: context,
        builder: (_) => _EditDialog(tile: existing),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.delete && existing != null) {
        _tiles.remove(existing);
      } else if (result.tile != null) {
        if (existing == null) {
          _tiles.add(result.tile!);
        } else {
          _tiles[_tiles.indexOf(existing)] = result.tile!;
        }
      }
    });
    await _save();
    await ShellMode.instance.applyBar(itemCount: _barItemCount);
  }

  Future<void> _add() async {
    final pick = await _inBigWindow<_PickResult>(
      () => showDialog<_PickResult>(
        context: context,
        builder: (_) => const _AddPicker(),
      ),
    );
    if (pick == null || !mounted) return;
    if (pick.manual) {
      await _edit(null);
      return;
    }
    setState(() => _tiles.add(pick.tile!));
    await _save();
    await ShellMode.instance.applyBar(itemCount: _barItemCount);
  }

  Future<void> _openSettings() async {
    await _inBigWindow<void>(
      () => showDialog<void>(context: context, builder: (_) => const _SettingsDialog()),
    );
  }

  Future<void> _powerMenu() async {
    final choice = await _inBigWindow<String>(
      () => showDialog<String>(
        context: context,
        builder: (ctx) => const QuickSettingsDialog(),
      ),
    );
    switch (choice) {
      case 'settings':
        await _openSettings();
      case 'sleep':
        await Launcher.sleep();
      case 'restart':
        await Launcher.restart();
      case 'shutdown':
        await Launcher.shutDown();
      case 'signout':
        await Launcher.signOut();
      case 'keyboard':
        await Launcher.screenKeyboard();
        await WindowsGamepadService.instance.waitForRelease();
        await ShellMode.instance.hide(resumePrevious: true);
      case 'hide':
        await WindowsGamepadService.instance.waitForRelease();
        await ShellMode.instance.hide();
      case 'exit':
        Freezer.instance.thawAll();
        await windowManager.destroy();
    }
  }

  // ---- bar ------------------------------------------------------------------

  Widget _divider() => Container(
    width: 1,
    height: 40,
    margin: const EdgeInsets.symmetric(horizontal: 8),
    color: Colors.white24,
  );

  Widget _imageOr(File? icon, Widget fallback) => icon == null
      ? fallback
      : Image.file(icon, width: 40, height: 40, filterQuality: FilterQuality.medium);

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    var first = true;
    bool af() {
      final v = first;
      first = false;
      return v;
    }

    for (final w in _open) {
      final letter = w.title.trim().isEmpty ? '?' : w.title.trim()[0].toUpperCase();
      final hue = (w.title.hashCode % 360).abs().toDouble();
      final fallbackColor = HSLColor.fromAHSL(1, hue, 0.45, 0.32).toColor();
      final icon = _iconFor(w.exePath);
      items.add(
        _BarItem(
          key: ValueKey('w${w.hwnd}'),
          label: Freezer.instance.isFrozen(OpenWindows.instance.pidOf(w.hwnd)) ? '${w.title}  (paused)' : w.title,
          color: icon != null ? const Color(0xFF232B3F) : fallbackColor,
          dot: true,
          autofocus: af(),
          onTap: () => _switchTo(w),
          onOptions: () => _closeWindow(w),
          onFocusLabel: (t) => _label.value = t,
          child: _imageOr(
            icon,
            Text(letter, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          ),
        ),
      );
    }
    if (_open.isNotEmpty && _tiles.isNotEmpty) items.add(_divider());
    for (final t in _tiles) {
      final icon = _iconFor(_tileExe(t));
      items.add(
        _BarItem(
          key: ValueKey('t${t.id}'),
          label: t.name,
          color: icon != null
              ? const Color(0xFF232B3F)
              : kTileColors[t.color.clamp(0, kTileColors.length - 1)],
          autofocus: af(),
          onTap: () => _launch(t),
          onOptions: () => _edit(t),
          onFocusLabel: (t) => _label.value = t,
          child: _imageOr(icon, Icon(kTileIcons[t.icon] ?? Icons.apps_rounded, size: 30)),
        ),
      );
    }
    items.add(_divider());
    items.add(
      _BarItem(
        key: const ValueKey('add'),
        label: 'Add an app or link',
        color: const Color(0xFF232B3F),
        autofocus: af(),
        onTap: _add,
        onFocusLabel: (t) => _label.value = t,
        child: const Icon(Icons.add_rounded, size: 30),
      ),
    );
    items.add(
      _BarItem(
        key: const ValueKey('settings'),
        label: 'Settings (bar button, hold time, freeze)',
        color: const Color(0xFF232B3F),
        onTap: _openSettings,
        onFocusLabel: (t) => _label.value = t,
        child: const Icon(Icons.settings_rounded, size: 30),
      ),
    );
    items.add(
      _BarItem(
        key: const ValueKey('power'),
        label: 'Quick settings & power',
        color: const Color(0xFF232B3F),
        onTap: _powerMenu,
        onFocusLabel: (t) => _label.value = t,
        child: const Icon(Icons.power_settings_new_rounded, size: 30),
      ),
    );

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): _HideBarIntent(),
        SingleActivator(LogicalKeyboardKey.f3): _AddIntent(),
      },
      child: Actions(
        actions: {
          _AddIntent: CallbackAction<_AddIntent>(onInvoke: (_) {
            if (!_busyDialog) _add();
            return null;
          }),
          _HideBarIntent: CallbackAction<_HideBarIntent>(onInvoke: (_) {
            if (!_busyDialog) ShellMode.instance.leave();
            return null;
          }),
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF11151F),
          body: Padding(
            padding: EdgeInsets.fromLTRB(16, _slim ? 8 : 12, 16, 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 66,
                  child: Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(mainAxisSize: MainAxisSize.min, children: items),
                    ),
                  ),
                ),
                if (!_slim) const SizedBox(height: 4),
                if (!_slim)
                ValueListenableBuilder<String>(
                  valueListenable: _label,
                  builder: (_, v, __) => Text(
                    v,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                ),
                if (!_slim) const SizedBox(height: 6),
                if (!_slim)
                const Wrap(
                  spacing: 18,
                  children: [
                    _Hint('A', 'Open', Color(0xFF51CF66)),
                    _Hint('X', 'Close / Edit', Color(0xFF4DABF7)),
                    _Hint('Y', 'Add', Color(0xFFFFD43B)),
                    _Hint('B', 'Hide', Color(0xFFFF6B6B)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.button, this.text, this.color);
  final String button;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Text(button,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: Colors.black)),
      ),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(fontSize: 14, color: Colors.white60)),
    ]);
  }
}

class _AddIntent extends Intent {
  const _AddIntent();
}

class _PickResult {
  _PickResult({this.tile, this.manual = false});
  final ShellTile? tile;
  final bool manual;
}

/// Controller-friendly "add to the bar" list: open apps, quick links,
/// installed apps (Start menu), or type it yourself.
class _AddPicker extends StatefulWidget {
  const _AddPicker();

  @override
  State<_AddPicker> createState() => _AddPickerState();
}

class _AddPickerState extends State<_AddPicker> {
  List<_Candidate> _installed = [];
  bool _loading = true;
  late final List<_Candidate> _running;

  static const _links = [
    ['YouTube', 'https://www.youtube.com'],
    ['Netflix', 'https://www.netflix.com'],
    ['Disney+', 'https://www.disneyplus.com'],
    ['Prime Video', 'https://www.primevideo.com'],
    ['Twitch', 'https://www.twitch.tv'],
    ['Spotify', 'https://open.spotify.com'],
    ['Google', 'https://www.google.com'],
  ];

  @override
  void initState() {
    super.initState();
    final seen = <String>{};
    _running = [
      for (final w in OpenWindows.instance.list())
        if (w.exePath.isNotEmpty && seen.add(w.exePath.toLowerCase()))
          _Candidate(w.title, w.exePath, 'app'),
    ];
    _scan();
  }

  Future<void> _scan() async {
    final found = <String, _Candidate>{};
    final roots = [
      '${Platform.environment['ProgramData'] ?? r'C:\ProgramData'}\\Microsoft\\Windows\\Start Menu\\Programs',
      '${Platform.environment['APPDATA'] ?? ''}\\Microsoft\\Windows\\Start Menu\\Programs',
    ];
    final skip = RegExp(r'uninstall|readme|help|documentation|license|release notes', caseSensitive: false);
    for (final root in roots) {
      try {
        final dir = Directory(root);
        if (!dir.existsSync()) continue;
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is! File || !e.path.toLowerCase().endsWith('.lnk')) continue;
          final file = e.path.split('\\').last;
          final name = file.substring(0, file.length - 4);
          if (skip.hasMatch(name)) continue;
          found.putIfAbsent(name.toLowerCase(), () => _Candidate(name, e.path, 'app'));
        }
      } catch (_) {}
    }
    final list = found.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (mounted) {
      setState(() {
        _installed = list;
        _loading = false;
      });
    }
  }

  ShellTile _tileOf(_Candidate c) => ShellTile(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    name: c.name,
    kind: c.kind,
    target: c.target,
    icon: c.kind == 'link' ? 'web' : 'apps',
    color: c.name.hashCode.abs() % kTileColors.length,
  );

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text,
        style: const TextStyle(fontSize: 16, color: Colors.white54, fontWeight: FontWeight.w600)),
  );

  Widget _row(IconData icon, String text, VoidCallback onTap, {bool autofocus = false}) =>
      ListTile(
        autofocus: autofocus,
        leading: Icon(icon),
        title: Text(text, style: const TextStyle(fontSize: 19)),
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    var first = true;
    bool af() {
      final v = first;
      first = false;
      return v;
    }

    return Dialog(
      child: SizedBox(
        width: 640,
        height: 560,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Add to the bar',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  _row(Icons.keyboard_rounded, 'Type a path or link myself (keyboard / mouse)',
                      () => Navigator.pop(context, _PickResult(manual: true)),
                      autofocus: af()),
                  if (_running.isNotEmpty) _header('Open right now'),
                  for (final c in _running)
                    _row(Icons.window_rounded, c.name,
                        () => Navigator.pop(context, _PickResult(tile: _tileOf(c))),
                        ),
                  _header('Quick links'),
                  for (final l in _links)
                    _row(Icons.public_rounded, l[0],
                        () => Navigator.pop(
                              context,
                              _PickResult(tile: _tileOf(_Candidate(l[0], l[1], 'link'))),
                            )),
                  _header(_loading ? 'Installed apps (loading...)' : 'Installed apps'),
                  for (final c in _installed)
                    _row(Icons.apps_rounded, c.name,
                        () => Navigator.pop(context, _PickResult(tile: _tileOf(c)))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Candidate {
  _Candidate(this.name, this.target, this.kind);
  final String name;
  final String target;
  final String kind;
}

class _HideBarIntent extends Intent {
  const _HideBarIntent();
}

class _BarItem extends StatefulWidget {
  const _BarItem({
    super.key,
    required this.child,
    required this.color,
    required this.label,
    required this.onTap,
    required this.onFocusLabel,
    this.onOptions,
    this.dot = false,
    this.autofocus = false,
  });
  final Widget child;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onOptions;
  final void Function(String) onFocusLabel;

  /// Small dot under the item = this app is open right now.
  final bool dot;
  final bool autofocus;

  @override
  State<_BarItem> createState() => _BarItemState();
}

class _BarItemState extends State<_BarItem> {
  bool _focused = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = _focused || _hover;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Focus(
        autofocus: widget.autofocus,
        onFocusChange: (f) {
          setState(() => _focused = f);
          if (f) {
            widget.onFocusLabel(widget.label);
            Scrollable.ensureVisible(context,
                duration: const Duration(milliseconds: 120), alignment: 0.5);
          }
        },
        onKeyEvent: (_, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          final k = e.logicalKey;
          if (k == LogicalKeyboardKey.enter ||
              k == LogicalKeyboardKey.numpadEnter ||
              k == LogicalKeyboardKey.select ||
              k == LogicalKeyboardKey.space) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          if (widget.onOptions != null &&
              (k == LogicalKeyboardKey.mediaPlayPause ||
                  k == LogicalKeyboardKey.contextMenu ||
                  k == LogicalKeyboardKey.f2)) {
            widget.onOptions!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          onEnter: (_) {
            setState(() => _hover = true);
            widget.onFocusLabel(widget.label);
          },
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: widget.onTap,
            onSecondaryTap: widget.onOptions,
            onLongPress: widget.onOptions,
            child: AnimatedScale(
              scale: active ? 1.1 : 1.0,
              duration: const Duration(milliseconds: 100),
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _focused ? Colors.white : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: widget.child,
                  ),
                  if (widget.dot)
                    Positioned(
                      bottom: 3,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF51CF66),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditResult {
  _EditResult({this.tile, this.delete = false});
  final ShellTile? tile;
  final bool delete;
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({this.tile});
  final ShellTile? tile;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _target;
  late final TextEditingController _args;
  late String _kind;
  late String _icon;
  late int _color;

  @override
  void initState() {
    super.initState();
    final t = widget.tile;
    _name = TextEditingController(text: t?.name ?? '');
    _target = TextEditingController(text: t?.target ?? '');
    _args = TextEditingController(text: t?.args ?? '');
    _kind = t?.kind ?? 'app';
    _icon = t?.icon ?? 'apps';
    _color = t?.color ?? 0;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _args.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty) return;
    Navigator.pop(
      context,
      _EditResult(
        tile: ShellTile(
          id: widget.tile?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
          name: _name.text.trim(),
          kind: _kind,
          target: _target.text.trim(),
          args: _args.text.trim(),
          icon: _icon,
          color: _color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.tile == null ? 'Add a tile' : 'Edit tile'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'app', label: Text('Program'), icon: Icon(Icons.apps_rounded)),
                  ButtonSegment(value: 'link', label: Text('Link'), icon: Icon(Icons.link_rounded)),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _target,
                decoration: InputDecoration(
                  labelText: _kind == 'app'
                      ? r'Full path to the .exe (example: C:\Games\app.exe)'
                      : 'Web address or link (example: https://… or steam://…)',
                ),
              ),
              if (_kind == 'app') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _args,
                  decoration: const InputDecoration(labelText: 'Extra options (optional)'),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in kTileIcons.entries)
                  ChoiceChip(
                    label: Icon(e.value),
                    selected: _icon == e.key,
                    onSelected: (_) => setState(() => _icon = e.key),
                  ),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                for (var i = 0; i < kTileColors.length; i++)
                  InkWell(
                    onTap: () => setState(() => _color = i),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: kTileColors[i],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == i ? Colors.white : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ]),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.tile != null)
          TextButton(
            onPressed: () => Navigator.pop(context, _EditResult(delete: true)),
            child: const Text('Delete'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  final s = ShellSettings.instance;
  bool _recording = false;
  bool _autostart = false;
  String _status = '';

  static const _holds = [0, 250, 500, 1000, 1500, 2000, 3000];

  @override
  void initState() {
    super.initState();
    Autostart.isEnabled().then((v) {
      if (mounted) setState(() => _autostart = v);
    });
  }

  bool _swallow(KeyEvent e) => true; // keep recorded keys from clicking buttons

  Future<void> _record() async {
    setState(() {
      _recording = true;
      _status = 'Press and HOLD the button(s) you want — all at once — then let go...';
    });
    HardwareKeyboard.instance.addHandler(_swallow);
    final result = await WindowsGamepadService.instance.record();
    HardwareKeyboard.instance.removeHandler(_swallow);
    if (!mounted) return;
    if (result != null && !result.isEmpty) {
      s.shortcut = result;
      await s.save();
      setState(() {
        _recording = false;
        _status = 'Saved: ${result.describe()}';
      });
    } else {
      setState(() {
        _recording = false;
        _status = 'Nothing was pressed — nothing changed.';
      });
    }
  }

  @override
  void dispose() {
    WindowsGamepadService.instance.cancelRecording();
    HardwareKeyboard.instance.removeHandler(_swallow);
    super.dispose();
  }

  String get _holdText =>
      s.holdMs == 0 ? 'Just press (no hold)' : '${(s.holdMs / 1000).toStringAsFixed(2)} seconds';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: (MediaQuery.of(context).size.width * 0.85).clamp(660.0, 960.0),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: SingleChildScrollView(
           child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ListTile(
                autofocus: true,
                enabled: !_recording,
                leading: const Icon(Icons.gamepad_rounded),
                title: const Text('Button that opens the bar', style: TextStyle(fontSize: 19)),
                subtitle: Text(s.shortcut.describe(), style: const TextStyle(fontSize: 15)),
                trailing: const Text('Change'),
                onTap: _record,
              ),
              ListTile(
                enabled: !_recording,
                leading: const Icon(Icons.timer_rounded),
                title: const Text('How long to hold it', style: TextStyle(fontSize: 19)),
                subtitle: Text(_holdText, style: const TextStyle(fontSize: 15)),
                trailing: const Text('Next'),
                onTap: () {
                  final i = _holds.indexOf(s.holdMs);
                  setState(() => s.holdMs = _holds[(i + 1) % _holds.length]);
                  s.save();
                },
              ),
              SwitchListTile(
                value: _autostart,
                title: const Text('Start with Windows', style: TextStyle(fontSize: 19)),
                subtitle: const Text('Everything Bar opens by itself when you turn on / restart the PC',
                    style: TextStyle(fontSize: 15)),
                onChanged: (v) async {
                  final ok = await Autostart.set(v);
                  if (mounted && ok) {
                    setState(() => _autostart = v);
                    ShellSettings.instance.autostartOff = !v;
                    ShellSettings.instance.save();
                  }
                },
              ),
              SwitchListTile(
                value: s.pinned,
                title: const Text('Keep the bar on screen all the time', style: TextStyle(fontSize: 19)),
                subtitle: const Text('Shrinks to just icons while you use another app; your button brings it back into focus',
                    style: TextStyle(fontSize: 15)),
                onChanged: (v) {
                  setState(() => s.pinned = v);
                  s.save();
                },
              ),
              SwitchListTile(
                value: s.keepFrozen,
                title: const Text('Keep the app you left paused', style: TextStyle(fontSize: 19)),
                subtitle: const Text('When you open another app, the one you left stays paused until you switch back to it',
                    style: TextStyle(fontSize: 15)),
                onChanged: (v) {
                  setState(() => s.keepFrozen = v);
                  s.save();
                },
              ),
              SwitchListTile(
                value: s.freeze,
                title: const Text('Freeze the app behind the bar', style: TextStyle(fontSize: 19)),
                subtitle: const Text('Pauses the game/app while the bar is open so it ignores the controller',
                    style: TextStyle(fontSize: 15)),
                onChanged: (v) {
                  setState(() => s.freeze = v);
                  s.save();
                },
              ),
              ListTile(
                enabled: !_recording,
                leading: const Icon(Icons.restore_rounded),
                title: const Text('Reset to Guide button, hold 1 second', style: TextStyle(fontSize: 19)),
                onTap: () {
                  setState(() {
                    s.shortcut = ShellShortcut.guide;
                    s.holdMs = 1000;
                    _status = 'Reset.';
                  });
                  s.save();
                },
              ),
              if (_status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(_status, style: const TextStyle(fontSize: 16, color: Colors.amberAccent)),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  'Ctrl+Alt+H always opens the bar too. Remotes that act like a keyboard work — '
                  'press their button when recording.',
                  style: TextStyle(fontSize: 14, color: Colors.white54),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _recording ? null : () => Navigator.pop(context),
                  child: const Text('Done', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
           ),
          ),
        ),
      ),
    );
  }
}
