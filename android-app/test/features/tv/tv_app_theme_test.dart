import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/core/tv_app_tokens.dart';
import 'package:tv_king/features/tv/core/tv_comfort.dart';
import 'package:tv_king/features/tv/core/tv_ghost.dart';
import 'package:tv_king/features/tv/core/tv_tokens.dart';

class _ThemeProbe extends StatefulWidget {
  const _ThemeProbe({required this.onInit});
  final VoidCallback onInit;
  @override
  State<_ThemeProbe> createState() => _ThemeProbeState();
}

class _ThemeProbeState extends State<_ThemeProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) {
    final palette = TvAppTokens.of(context);
    return ColoredBox(
      key: const Key('surface'),
      color: palette.bg,
      child: Text('Texte', style: TextStyle(color: palette.text)),
    );
  }
}

void main() {
  test(
    'Noir Fantôme reste OLED et platine avec un thème clair doré du panel',
    () {
      const palette = TvAppTokens(
        ghost: true,
        light: true,
        remoteAccent: TvTokens.accent,
      );
      expect(palette.light, isFalse);
      expect(palette.bg, Colors.black);
      expect(palette.panel, TvGhost.panel);
      expect(palette.card, TvGhost.card);
      expect(palette.text, TvGhost.text);
      expect(palette.accent, TvGhost.chrome);
      expect(palette.accentBright, TvGhost.chromeBright);
      expect(palette.accentDeep, TvGhost.chromeDeep);
      expect(palette.onAccent, TvGhost.onChrome);
      expect((palette.bgGradient as RadialGradient).colors, <Color>[
        Colors.black,
        Colors.black,
      ]);

      // La priorité visuelle ne détruit pas les réglages du panel :
      // l'option Confort retrouve réellement leur palette.
      final comfort = palette.copyWith(ghost: false);
      expect(palette.remoteAccent, TvTokens.accent);
      expect(comfort.light, isTrue);
      expect(comfort.bg, const TvAppTokens(light: true).bg);
      expect(comfort.accent, TvTokens.accent);
    },
  );

  test('une animation de thème Ghost conserve le choix clair du panel', () {
    const before = TvAppTokens(
      ghost: true,
      light: true,
      remoteAccent: Colors.blue,
    );
    const after = TvAppTokens(
      ghost: true,
      light: true,
      remoteAccent: TvTokens.accent,
    );
    final during = before.lerp(after, .5);
    expect(during.light, isFalse);
    expect(during.bg, Colors.black);
    expect(during.accent, TvGhost.chrome);
    final comfort = during.copyWith(ghost: false);
    expect(comfort.light, isTrue);
    expect(comfort.accent, Color.lerp(Colors.blue, TvTokens.accent, .5));
  });

  test('sans réglage panel, le soir confort remplace le noir historique', () {
    const palette = TvAppTokens();
    final comfort = TvComfortPalette.of(TvComfortPeriod.evening);
    expect(palette.period, TvComfortPeriod.evening);
    expect(palette.bg, comfort.bg);
    expect(palette.bg, isNot(TvTokens.bg));
    expect(palette.bg, isNot(const Color(0xFF000000)));
    expect(palette.text, isNot(const Color(0xFFFFFFFF)));
    expect(palette.accent, TvTokens.accent);
    expect(palette.accentBright, TvTokens.accentBright);
    expect(palette.onAccent, TvTokens.onAccent);
    expect(palette.brandGlow, TvTokens.brandGlow);
    expect(palette.pillGradient, TvTokens.pillGradient);
    // Le bouton n'utilise plus le reflet vif en grand aplat.
    final LinearGradient cta = palette.ctaGradient as LinearGradient;
    expect(cta.colors, <Color>[TvTokens.accent, TvTokens.accent]);
  });

  test('les commandes Cast gardent la palette historique figée', () {
    expect(TvTokens.bg, const Color(0xFF070708));
    expect(TvTokens.accent, const Color(0xFFC99A3A));
    expect(TvTokens.accentBright, const Color(0xFFF2CF7A));
    expect(TvTokens.live, const Color(0xFFFF4D3D));
    expect(TvTokens.text, const Color(0xFFF0EDE9));
  });

  test(
      'les modes clair et sombre gardent du contraste avec les accents extrêmes',
      () {
    for (final light in <bool>[true, false]) {
      for (final accent in <Color>[
        Colors.white,
        Colors.black,
        Colors.yellow,
        Color(0xFF1E8E4E),
        Color(0xFF2E7DD6),
        Color(0xFFD6A030)
      ]) {
        final palette = TvAppTokens(light: light, remoteAccent: accent);
        expect(TvAppTokens.contrast(palette.text, palette.bg),
            greaterThanOrEqualTo(4.5));
        expect(TvAppTokens.contrast(palette.muted, palette.card),
            greaterThanOrEqualTo(4.5));
        expect(TvAppTokens.contrast(palette.accentBright, palette.bg),
            greaterThanOrEqualTo(4.5));
        expect(TvAppTokens.contrast(palette.onAccent, palette.accent),
            greaterThanOrEqualTo(4.5));
      }
    }
  });

  testWidgets('changer le thème reconstruit les couleurs sans perdre le State',
      (tester) async {
    int inits = 0;
    final child = _ThemeProbe(onInit: () => inits++);
    Future<void> show(TvAppTokens palette) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: <ThemeExtension<dynamic>>[palette]),
        home: child,
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

  testWidgets('les superpositions vidéo restent sombres en mode clair',
      (tester) async {
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
    expect(playback.bg, TvComfortPalette.of(TvComfortPeriod.evening).bg);
    expect(playback.text, isNot(const Color(0xFF202026)));
    expect(playback.accent, Colors.green);
  });
}
