import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/core/tv_app_tokens.dart';
import 'package:tv_king/features/tv/core/tv_comfort.dart';
import 'package:tv_king/features/tv/core/tv_comfort_schedule.dart';
import 'package:tv_king/features/tv/core/tv_glass.dart';
import 'package:tv_king/features/tv/core/tv_tokens.dart';

void main() {
  test('le fond est une obsidienne, le halo cuivré reste local', () {
    final day = TvComfortPalette.of(TvComfortPeriod.day);
    final evening = TvComfortPalette.of(TvComfortPeriod.evening);
    final night = TvComfortPalette.of(TvComfortPeriod.night);
    const Color materialGray = Color(0xFF121212);

    expect(day.bg.r, day.bg.g);
    expect(day.bg.g, day.bg.b);
    expect(day.bg, isNot(const Color(0xFF000000)));
    expect(
        day.bg.computeLuminance(), lessThan(materialGray.computeLuminance()));

    expect(evening.bg.r, greaterThan(evening.bg.b));
    expect(evening.bg, isNot(const Color(0xFF000000)));
    expect(evening.bg.computeLuminance(),
        lessThan(materialGray.computeLuminance()));
    expect(evening.card.a, lessThan(1));
    expect(evening.glassFill, evening.card);
    // Le centre du halo est plus clair que l'obsidienne, et plus chaud.
    expect(evening.ambientPeak.computeLuminance(),
        greaterThan(evening.bg.computeLuminance()));
    expect(evening.ambientPeak.r, greaterThan(evening.ambientPeak.b));
    expect(evening.ambientPeak.computeLuminance(), lessThan(0.04));
    expect(night.ambientPeak.computeLuminance(),
        lessThan(evening.ambientPeak.computeLuminance()));
    expect(
        night.bg.computeLuminance(), lessThan(evening.bg.computeLuminance()));
  });

  test('texte, accent et direct passent WCAG sur chaque moment', () {
    for (final TvComfortPeriod period in TvComfortPeriod.values) {
      final palette = TvAppTokens(period: period);
      final Color peak = TvComfortPalette.of(period).ambientPeak;
      // Le verre est translucide : on mesure ce qu'on voit sur le halo,
      // pas la couleur avant mélange (son alpha fausse la luminance).
      final List<Color> surfaces = <Color>[
        palette.bg,
        for (final Color glass in <Color>[
          palette.panel,
          palette.card,
          palette.sel,
          palette.surface3,
        ])
          TvComfortPalette.seen(glass, peak),
      ];
      for (final Color surface in surfaces) {
        expect(
          TvAppTokens.contrast(palette.text, surface),
          greaterThanOrEqualTo(7),
          reason: '$period texte / $surface',
        );
        expect(
          TvAppTokens.contrast(palette.muted, surface),
          greaterThanOrEqualTo(4.5),
          reason: '$period secondaire / $surface',
        );
        expect(
          TvAppTokens.contrast(palette.mutedDim, surface),
          greaterThanOrEqualTo(4.5),
          reason: '$period tertiaire / $surface',
        );
        expect(
          TvAppTokens.contrast(palette.accent, surface),
          greaterThanOrEqualTo(4.5),
          reason: '$period or / $surface',
        );
        expect(
          TvAppTokens.contrast(palette.accentBright, surface),
          greaterThanOrEqualTo(4.5),
          reason: '$period focus / $surface',
        );
        expect(
          TvAppTokens.contrast(palette.live, surface),
          greaterThanOrEqualTo(4.5),
          reason: '$period direct / $surface',
        );
        expect(
          TvAppTokens.contrast(palette.success, surface),
          greaterThanOrEqualTo(4.5),
          reason: '$period succès / $surface',
        );
      }
      expect(TvAppTokens.contrast(palette.onAccent, palette.accent),
          greaterThanOrEqualTo(4.5));
      expect(TvAppTokens.contrast(palette.onLive, palette.live),
          greaterThanOrEqualTo(4.5));
      expect(palette.text.computeLuminance(), lessThan(0.95));
      expect(palette.mutedDim.computeLuminance(),
          lessThanOrEqualTo(palette.muted.computeLuminance()));
      expect(palette.muted.computeLuminance(),
          lessThan(palette.text.computeLuminance()));
    }
  });

  test('le mode clair du panel garde son contraste, y compris sur le direct',
      () {
    const palette = TvAppTokens(light: true);
    expect(TvAppTokens.contrast(palette.onLive, palette.live),
        greaterThanOrEqualTo(4.5));
    expect(palette.bg, const Color(0xFFF6F5F2));
  });

  test('les heures locales tranchent le moment sans géolocalisation', () {
    expect(TvComfortPalette.fromHour(0), TvComfortPeriod.night);
    expect(TvComfortPalette.fromHour(6), TvComfortPeriod.night);
    expect(TvComfortPalette.fromHour(7), TvComfortPeriod.day);
    expect(TvComfortPalette.fromHour(16), TvComfortPeriod.day);
    expect(TvComfortPalette.fromHour(17), TvComfortPeriod.evening);
    expect(TvComfortPalette.fromHour(21), TvComfortPeriod.evening);
    expect(TvComfortPalette.fromHour(22), TvComfortPeriod.night);
    final DateTime afternoon = DateTime(2026, 11, 4, 16, 30);
    expect(TvComfortPalette.nextBoundary(afternoon), DateTime(2026, 11, 4, 17));
    expect(
      TvComfortPalette.nextBoundary(DateTime(2026, 11, 4, 22, 10)),
      DateTime(2026, 11, 5, 7),
    );
  });

  test('le choix auto lit l\'horloge et le soir fixe ne la lit pas', () {
    final schedule = TvComfortSchedule.instance;
    addTearDown(() => schedule.debugChoose(TvComfortChoice.evening));
    schedule.debugChoose(
      TvComfortChoice.auto,
      clock: () => DateTime(2026, 11, 4, 23),
    );
    expect(schedule.period, TvComfortPeriod.night);
    schedule.debugChoose(TvComfortChoice.evening);
    expect(schedule.period, TvComfortPeriod.evening);
  });

  testWidgets('le verre ne floute pas tant que la box est lente',
      (tester) async {
    TvGlassPolicy.debugSetCapable(false);
    addTearDown(() => TvGlassPolicy.debugSetCapable(false));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const <ThemeExtension<dynamic>>[
        TvAppTokens(),
      ]),
      home: const TvGlass(child: Text('Ce soir')),
    ));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('Ce soir'), findsOneWidget);

    TvGlassPolicy.debugSetCapable(true);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const <ThemeExtension<dynamic>>[
        TvAppTokens(),
      ]),
      home: const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: TvGlass(child: Text('Ce soir')),
      ),
    ));
    expect(find.byType(BackdropFilter), findsNothing);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const <ThemeExtension<dynamic>>[
        TvAppTokens(),
      ]),
      home: const TvGlass(child: Text('Ce soir')),
    ));
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  test('le puits vidéo reste noir pur et sans filtre de couleur', () {
    final String player = File(
      'lib/features/tv/presentation/tv_player_screen.dart',
    ).readAsStringSync();
    expect(player, contains('color: Colors.black'));
    expect(player, isNot(contains('ColorFiltered')));
    expect(player, isNot(contains('ImageFilter')));
    final String glass =
        File('lib/features/tv/core/tv_glass.dart').readAsStringSync();
    expect(glass, contains('allowsBlur'));
    expect(glass, contains('if (!frost) return pane'));
  });
}
