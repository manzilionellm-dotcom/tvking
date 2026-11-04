// Aperçu LOCAL du thème confort. Ce n'est pas le point d'entrée de la
// box (`lib/main_tv.dart`). Aucune source, aucun flux, aucun identifiant.
//
//   flutter run -t lib/dev/comfort_preview_main.dart --dart-define=COMFORT_PREVIEW=before
//   flutter run -t lib/dev/comfort_preview_main.dart --dart-define=COMFORT_PREVIEW=after

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/bundled_fonts.dart';
import '../features/tv/core/tv_app_tokens.dart';
import '../features/tv/core/tv_comfort.dart';
import '../features/tv/core/tv_dimens.dart';
import '../features/tv/core/tv_tokens.dart';

const String _mode =
    String.fromEnvironment('COMFORT_PREVIEW', defaultValue: 'after');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  configureTvFontLoading();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  const bool historical = _mode == 'before';
  const TvAppTokens palette = historical
      ? _HistoricalTokens()
      : TvAppTokens(period: TvComfortPeriod.evening);
  runApp(ComfortPreviewApp(palette: palette, historical: historical));
}

/// Ancien Maison Noir, figé dans [TvTokens], pour la capture « avant ».
class _HistoricalTokens extends TvAppTokens {
  const _HistoricalTokens() : super(period: TvComfortPeriod.evening);

  @override
  Color get bg => TvTokens.bg;
  @override
  Color get panel => TvTokens.panel;
  @override
  Color get card => TvTokens.card;
  @override
  Color get tile => TvTokens.tile;
  @override
  Color get sel => TvTokens.sel;
  @override
  Color get surface3 => TvTokens.surface3;
  @override
  Color get line => TvTokens.line;
  @override
  Color get lineSoft => TvTokens.lineSoft;
  @override
  Color get text => TvTokens.text;
  @override
  Color get muted => TvTokens.muted;
  @override
  Color get mutedDim => TvTokens.mutedDim;
  @override
  Color get live => TvTokens.live;
  @override
  Gradient get bgGradient => TvTokens.bgGradient;
  @override
  Gradient get ctaGradient => TvTokens.ctaGradient;
}

class ComfortPreviewApp extends StatelessWidget {
  const ComfortPreviewApp(
      {super.key, required this.palette, required this.historical});

  final TvAppTokens palette;
  final bool historical;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: palette.bg,
        extensions: <ThemeExtension<dynamic>>[palette],
        splashFactory: NoSplash.splashFactory,
      ),
      home: const ComfortPreview(),
    );
  }
}

class ComfortPreview extends StatelessWidget {
  const ComfortPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final TvAppTokens c = TvAppTokens.of(context);
    const bool historical =
        String.fromEnvironment('COMFORT_PREVIEW', defaultValue: 'after') ==
            'before';
    return Scaffold(
      backgroundColor: c.bg,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: TvDimens.safeH, vertical: TvDimens.safeV),
          child: Row(
            children: <Widget>[
              _Rail(palette: c),
              const SizedBox(width: 36),
              Expanded(child: _Stage(palette: c, historical: historical)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.palette});
  final TvAppTokens palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(TvTokens.rCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Zuno', style: palette.display(TvDimens.headline, spacing: 1)),
          const SizedBox(height: 28),
          _Item(palette: palette, label: 'Accueil', on: true),
          _Item(palette: palette, label: 'Direct'),
          _Item(palette: palette, label: 'Cinéma'),
          _Item(palette: palette, label: 'Réglages'),
          const Spacer(),
          Text(
            'Soir',
            style: palette.ui(TvDimens.caption, color: palette.muted),
          ),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.palette, required this.label, this.on = false});
  final TvAppTokens palette;
  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: on ? palette.sel : Colors.transparent,
        borderRadius: BorderRadius.circular(TvTokens.rMenuItem),
        border: Border.all(
          color: on ? palette.accent : Colors.transparent,
          width: TvDimens.focusOutline,
        ),
      ),
      child: Text(
        label,
        style: palette.ui(
          TvDimens.label,
          weight: on ? FontWeight.w600 : FontWeight.w400,
          color: on ? palette.accentBright : palette.text,
        ),
      ),
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage({required this.palette, required this.historical});
  final TvAppTokens palette;
  final bool historical;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          historical ? 'Avant  ·  Maison Noir' : 'Après  ·  Confort du soir',
          style:
              palette.ui(TvDimens.caption, color: palette.muted, spacing: 1.2),
        ),
        const SizedBox(height: 8),
        Text(
          'Ce soir',
          style: palette.display(TvDimens.displayM),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 640,
          child: Text(
            'Fond gris chaud, or calme, texte ivoire. Lisible à trois mètres.',
            style: palette.ui(TvDimens.body, color: palette.muted),
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: <Widget>[
            _Card(
                palette: palette,
                title: 'Journal',
                meta: 'Direct',
                focused: true),
            const SizedBox(width: 16),
            _Card(palette: palette, title: 'Documentaire', meta: '48 min'),
            const SizedBox(width: 16),
            _Card(palette: palette, title: 'Concert', meta: 'Ce soir'),
          ],
        ),
        const Spacer(),
        Row(
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: palette.ctaGradient,
                borderRadius: BorderRadius.circular(TvTokens.rButton),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                child: Text(
                  'Regarder',
                  style: palette.ui(TvDimens.label,
                      weight: FontWeight.w700, color: palette.onAccent),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: palette.live,
                borderRadius: BorderRadius.circular(TvTokens.rSmall),
              ),
              child: Text(
                'EN DIRECT',
                style: palette.ui(TvDimens.caption,
                    weight: FontWeight.w800, color: palette.onLive),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              'Focus  ·  or du logo',
              style: palette.ui(TvDimens.caption, color: palette.accentBright),
            ),
          ],
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.palette,
    required this.title,
    required this.meta,
    this.focused = false,
  });

  final TvAppTokens palette;
  final String title;
  final String meta;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      height: 148,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: focused ? palette.sel : palette.card,
        borderRadius: BorderRadius.circular(TvTokens.rCard),
        border: Border.all(
          color: focused ? palette.accentBright : palette.lineSoft,
          width: focused ? TvDimens.focusOutline : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: palette.tile,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const Spacer(),
          Text(title,
              style: palette.ui(TvDimens.titleS, weight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(meta,
              style: palette.ui(TvDimens.caption, color: palette.mutedDim)),
        ],
      ),
    );
  }
}
