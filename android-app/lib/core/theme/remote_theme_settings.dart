import 'package:flutter/material.dart';

/// Contrat de /api/theme. Vide signifie retirer une surcharge, tandis qu'une
/// réponse mal formée est refusée pour garder le dernier thème utilisable.
@immutable
class RemoteThemeSettings {
  const RemoteThemeSettings({this.appName = '', this.accent, this.mode});

  final String appName;
  final Color? accent;
  final ThemeMode? mode;

  static RemoteThemeSettings? parse(Object? value) {
    if (value is! Map ||
        !<String>['appName', 'accent', 'bg'].any(value.containsKey))
      return null;
    for (final key in <String>['appName', 'accent', 'bg']) {
      if (value[key] != null && value[key] is! String) return null;
    }
    final name = ((value['appName'] as String?) ?? '')
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
        .trim();
    final hex = ((value['accent'] as String?) ?? '').trim();
    final bg = ((value['bg'] as String?) ?? '').trim();
    if (hex.isNotEmpty && !RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(hex))
      return null;
    if (bg.isNotEmpty && bg != 'dark' && bg != 'light') return null;
    return RemoteThemeSettings(
      appName: name.length > 40 ? name.substring(0, 40) : name,
      accent: hex.isEmpty
          ? null
          : Color(0xFF000000 | int.parse(hex.replaceFirst('#', ''), radix: 16)),
      mode: bg.isEmpty
          ? null
          : (bg == 'light' ? ThemeMode.light : ThemeMode.dark),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RemoteThemeSettings &&
      other.appName == appName &&
      other.accent == accent &&
      other.mode == mode;
  @override
  int get hashCode => Object.hash(appName, accent, mode);
}
