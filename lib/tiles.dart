import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// One tile on the home screen: an app to start or a link to open.
class ShellTile {
  ShellTile({
    required this.id,
    required this.name,
    required this.kind,
    required this.target,
    this.args = '',
    this.icon = 'apps',
    this.color = 0,
  });

  final String id;
  String name;

  /// 'app' (a program on this PC) or 'link' (a web address or a Windows link
  /// such as steam://… or ms-settings:).
  String kind;
  String target;
  String args;
  String icon;
  int color;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind,
    'target': target,
    'args': args,
    'icon': icon,
    'color': color,
  };

  factory ShellTile.fromJson(Map<String, dynamic> json) => ShellTile(
    id: json['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
    name: json['name']?.toString() ?? 'App',
    kind: json['kind']?.toString() == 'link' ? 'link' : 'app',
    target: json['target']?.toString() ?? '',
    args: json['args']?.toString() ?? '',
    icon: json['icon']?.toString() ?? 'apps',
    color: int.tryParse(json['color']?.toString() ?? '') ?? 0,
  );
}

const Map<String, IconData> kTileIcons = {
  'apps': Icons.apps_rounded,
  'tv': Icons.tv_rounded,
  'games': Icons.sports_esports_rounded,
  'steam': Icons.videogame_asset_rounded,
  'folder': Icons.folder_rounded,
  'settings': Icons.settings_rounded,
  'web': Icons.public_rounded,
  'music': Icons.library_music_rounded,
  'movie': Icons.movie_rounded,
  'photo': Icons.photo_library_rounded,
};

const List<Color> kTileColors = [
  Color(0xFF3B5BDB),
  Color(0xFF0CA678),
  Color(0xFFD9480F),
  Color(0xFF9C36B5),
  Color(0xFFC2255C),
  Color(0xFF1098AD),
  Color(0xFF5F3DC4),
  Color(0xFF495057),
];

/// Saves the tiles in %APPDATA%\HomeShell\tiles.json.
class TileStore {
  static String get dir => '${Platform.environment['APPDATA'] ?? '.'}\\HomeShell';
  static File get _file => File('$dir\\tiles.json');

  static Future<List<ShellTile>> load() async {
    try {
      if (await _file.exists()) {
        final raw = jsonDecode(await _file.readAsString());
        if (raw is List) {
          final tiles = <ShellTile>[
            for (final item in raw)
              if (item is Map) ShellTile.fromJson(Map<String, dynamic>.from(item)),
          ];
          if (tiles.isNotEmpty) return tiles;
        }
      }
    } catch (_) {}
    final tiles = defaults();
    await save(tiles);
    return tiles;
  }

  static Future<void> save(List<ShellTile> tiles) async {
    try {
      await Directory(dir).create(recursive: true);
      await _file.writeAsString(
        const JsonEncoder.withIndent('  ').convert([
          for (final t in tiles) t.toJson(),
        ]),
      );
    } catch (_) {}
  }

  static List<ShellTile> defaults() => [
    ShellTile(
      id: 'debrify',
      name: 'Debrify',
      kind: 'app',
      target: r'C:\debrifyy\build\windows\x64\runner\Release\debrify.exe',
      icon: 'tv',
      color: 0,
    ),
    ShellTile(
      id: 'playnite',
      name: 'Playnite',
      kind: 'app',
      target: r'%LOCALAPPDATA%\Playnite\Playnite.FullscreenApp.exe',
      icon: 'games',
      color: 3,
    ),
    ShellTile(
      id: 'steam',
      name: 'Steam Big Picture',
      kind: 'link',
      target: 'steam://open/bigpicture',
      icon: 'steam',
      color: 5,
    ),
    ShellTile(
      id: 'files',
      name: 'Files',
      kind: 'app',
      target: 'explorer.exe',
      icon: 'folder',
      color: 7,
    ),
    ShellTile(
      id: 'settings',
      name: 'Windows Settings',
      kind: 'link',
      target: 'ms-settings:',
      icon: 'settings',
      color: 6,
    ),
    ShellTile(
      id: 'web',
      name: 'Web',
      kind: 'link',
      target: 'https://www.google.com',
      icon: 'web',
      color: 1,
    ),
  ];
}
