import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/core/tv_app_tokens.dart';
import 'package:tv_king/features/tv/core/tv_comfort.dart';
import 'package:tv_king/features/tv/core/tv_comfort_schedule.dart';
import 'package:tv_king/features/tv/core/tv_tokens.dart';

void main() {
  test(
      'le jour est le gris Material, le soir est plus chaud, la nuit plus sombre',
      () {
    final day = TvComfortPalette.of(TvComfortPeriod.day);
    final evening = TvComfortPalette.of(TvComfortPeriod.evening);
    final night = TvComfortPalette.of(TvComfortPeriod.night);

    expect(day.bg, const Color(0xFF121212));
    expect(day.bg.r, day.bg.g);
    expect(day.bg.g, day.bg.b);

    expect(evening.bg.r, greaterThan(evening.bg.b));
    expect(
        evening.bg.computeLuminance(), greaterThan(day.bg.computeLuminance()));
    expect(evening.bg.computeLuminance(), lessThan(0.03));

    final Color warmStop = (TvTokens.bgGradient as RadialGradient).colors.first;
    expect(night.bg, warmStop);
    expect(night.bg.b / night.bg.r, lessThan(evening.bg.b / evening.bg.r));
    expect(
        night.bg.computeLuminance(), lessThan(evening.bg.computeLuminance()));
    expect(night.bg, isNot(const Color(0xFF000000)));
  });

  test('texte, accent et direct passent WCAG sur chaque moment', () {
    for (final TvComfortPeriod period in TvComfortPeriod.values) {
      final palette = TvAppTokens(period: period);
      final List<Color> surfaces = <Color>[
        palette.bg,
        palette.panel,
        palette.card,
        palette.sel,
        palette.surface3,
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

  test('le puits vidéo reste noir pur et sans filtre de couleur', () {
    final String player = File(
      'lib/features/tv/presentation/tv_player_screen.dart',
    ).readAsStringSync();
    expect(player, contains('color: Colors.black'));
    expect(player, isNot(contains('ColorFiltered')));
    expect(player, isNot(contains('ImageFilter')));
    final String comfort =
        File('lib/features/tv/core/tv_comfort.dart').readAsStringSync();
    expect(comfort, isNot(contains('BackdropFilter')));
    expect(comfort, isNot(contains('ImageFilter')));
  });
}
