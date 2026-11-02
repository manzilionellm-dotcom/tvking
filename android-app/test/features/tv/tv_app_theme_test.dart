import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/core/tv_app_tokens.dart';
import 'package:tv_king/features/tv/core/tv_tokens.dart';

class _ThemeProbe extends StatefulWidget {
  const _ThemeProbe({required this.onInit});
  final VoidCallback onInit;
  @override
  State<_ThemeProbe> createState() => _ThemeProbeState();
}

class _ThemeProbeState extends State<_ThemeProbe> {
  @override
  void initState() { super.initState(); widget.onInit(); }
  @override
  Widget build(BuildContext context) {
    final palette = TvAppTokens.of(context);
    return ColoredBox(
      key: const Key('surface'), color: palette.bg,
      child: Text('Texte', style: TextStyle(color: palette.text)),
    );
  }
}

void main() {
  test('sans réglage panel, la palette TV garde les couleurs historiques', () {
    const palette = TvAppTokens();
    expect(<Color>[
      palette.bg, palette.panel, palette.card, palette.tile, palette.tileBorder,
      palette.badgeBg, palette.sel, palette.surface3, palette.line, palette.lineSoft,
      palette.text, palette.muted, palette.mutedDim, palette.accent,
      palette.accentBright, palette.accentDeep, palette.onAccent, palette.live, palette.success,
    ], <Color>[
      TvTokens.bg, TvTokens.panel, TvTokens.card, TvTokens.tile, TvTokens.tileBorder,
      TvTokens.badgeBg, TvTokens.sel, TvTokens.surface3, TvTokens.line, TvTokens.lineSoft,
      TvTokens.text, TvTokens.muted, TvTokens.mutedDim, TvTokens.accent,
      TvTokens.accentBright, TvTokens.accentDeep, TvTokens.onAccent, TvTokens.live, TvTokens.success,
    ]);
    expect(palette.bgGradient, TvTokens.bgGradient);
    expect(palette.brandGlow, TvTokens.brandGlow);
    expect(palette.accentHairline, TvTokens.accentHairline);
    expect(palette.ctaGradient, TvTokens.ctaGradient);
    expect(palette.pillGradient, TvTokens.pillGradient);
  });

  test('les modes clair et sombre gardent du contraste avec les accents extrêmes', () {
    for (final light in <bool>[true, false]) {
      for (final accent in <Color>[Colors.white, Colors.black, Colors.yellow,
          Color(0xFF1E8E4E), Color(0xFF2E7DD6), Color(0xFFD6A030)]) {
        final palette = TvAppTokens(light: light, remoteAccent: accent);
        expect(TvAppTokens.contrast(palette.text, palette.bg), greaterThanOrEqualTo(4.5));
        expect(TvAppTokens.contrast(palette.muted, palette.card), greaterThanOrEqualTo(4.5));
        expect(TvAppTokens.contrast(palette.accentBright, palette.bg), greaterThanOrEqualTo(4.5));
        expect(TvAppTokens.contrast(palette.onAccent, palette.accent), greaterThanOrEqualTo(4.5));
      }
    }
  });

  testWidgets('changer le thème reconstruit les couleurs sans perdre le State', (tester) async {
    int inits = 0;
    final child = _ThemeProbe(onInit: () => inits++);
    Future<void> show(TvAppTokens palette) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: <ThemeExtension<dynamic>>[palette]), home: child,
      ));
      await tester.pumpAndSettle();
    }
    await show(const TvAppTokens());
    final initial = tester.state(find.byType(_ThemeProbe));
    await show(const TvAppTokens(light: true, remoteAccent: Colors.blue));
    expect(tester.state(find.byType(_ThemeProbe)), same(initial));
    expect(inits, 1);
    expect(tester.widget<ColoredBox>(find.byKey(const Key('surface'))).color,
        const TvAppTokens(light: true).bg);
    expect(tester.widget<Text>(find.text('Texte')).style?.color,
        const TvAppTokens(light: true).text);
    // Les commandes Cast continuent à lire leur ancienne palette immuable.
    expect(TvTokens.bg, const Color(0xFF070708));
    expect(TvTokens.accent, const Color(0xFFC99A3A));
  });

  testWidgets('les superpositions vidéo restent sombres en mode clair', (tester) async {
    late TvAppTokens playback;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const <ThemeExtension<dynamic>>[
        TvAppTokens(light: true, remoteAccent: Colors.green),
      ]),
      home: Builder(builder: (context) {
        playback = TvAppTokens.playbackOf(context);
        return const SizedBox();
      }),
    ));
    expect(playback.light, isFalse);
    expect(playback.text, TvTokens.text);
    expect(playback.accent, Colors.green);
  });
}
