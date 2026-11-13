import 'package:flutter/material.dart';

/// Validated remote theme state. Semantic warning/live colours stay semantic.
/// No widget remount: widgets subscribe through the Material Theme dependency.
class RemotePalette extends ChangeNotifier {
  RemotePalette._();
  static final RemotePalette instance = RemotePalette._();
  bool _light = false;
  Color? _accent;
  bool get light => _light;
  Color? get accent => _accent;
  static void watch(BuildContext context) {
    Theme.of(context);
  }

  void apply({required String background, Color? accent}) {
    final bool next = background == 'light';
    if (next == _light && accent == _accent) return;
    _light = next;
    _accent = accent;
    notifyListeners();
  }

  Color resolve(String slot, Color fallback) {
    if (slot == 'accent') return _accent ?? fallback;
    if (slot == 'accentBright' || slot == 'accentDeep') {
      if (_accent == null) return fallback;
      final HSLColor hsl = HSLColor.fromColor(_accent!);
      return hsl
          .withLightness(
              (hsl.lightness + (slot == 'accentBright' ? 0.15 : -0.22))
                  .clamp(0.0, 1.0))
          .toColor();
    }
    if (!_light) return fallback;
    return switch (slot) {
      'background' => const Color(0xFFF4F4F6),
      'surface' => const Color(0xFFFFFFFF),
      'surfaceHigh' => const Color(0xFFE8E8EE),
      'overlay' => const Color(0xFFDCDCE4),
      'text' => const Color(0xFF181820),
      'secondary' => const Color(0xFF565660),
      'muted' => const Color(0xFF6B6B74),
      'border' => const Color(0x24000000),
      _ => fallback,
    };
  }

  ThemeData decorate(ThemeData base) {
    final Color bg = resolve('background', base.scaffoldBackgroundColor);
    final Color surface = resolve('surface', base.colorScheme.surface);
    final Color text = resolve('text', base.colorScheme.onSurface);
    final Brightness brightness = light ? Brightness.light : Brightness.dark;
    final ColorScheme scheme = base.colorScheme.copyWith(
        brightness: brightness,
        primary: accent ?? base.colorScheme.primary,
        surface: surface,
        onSurface: text);
    return base.copyWith(
        brightness: brightness,
        scaffoldBackgroundColor: bg,
        colorScheme: scheme,
        textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
        appBarTheme: base.appBarTheme
            .copyWith(backgroundColor: bg, foregroundColor: text));
  }
}
