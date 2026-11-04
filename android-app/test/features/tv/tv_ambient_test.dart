import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel_genre.dart';
import 'package:tv_king/features/tv/core/tv_ambient.dart';
import 'package:tv_king/features/tv/core/tv_comfort.dart';
import 'package:tv_king/features/tv/presentation/tv_player_screen.dart';
import 'dart:io';

void main() {
  final TvComfortPalette evening = TvComfortPalette.of(TvComfortPeriod.evening);

  // Une affiche de nuit (ambres) et une pelouse (verts). Les blancs
  // et les noirs du cadre sont ignorés par la moyenne.
  const List<int> film = <int>[
    140,
    62,
    36,
    96,
    44,
    28,
    8,
    6,
    5,
    250,
    250,
    250,
  ];
  const List<int> pitch = <int>[
    36,
    130,
    48,
    24,
    150,
    64,
    4,
    6,
    4,
    248,
    248,
    248,
  ];

  test('le film est plus sombre et plus chaud que le football, sous 10 %', () {
    final Color filmSeed = TvAmbientMath.averageRgb(film);
    final Color pitchSeed = TvAmbientMath.averageRgb(pitch);
    expect(filmSeed.r, greaterThan(filmSeed.b));
    expect(pitchSeed.g, greaterThan(pitchSeed.r));

    final TvAmbientLook cinema = TvAmbientMath.look(
      mood: TvAmbientMood.cinema,
      seed: filmSeed,
      evening: evening,
    );
    final TvAmbientLook sport = TvAmbientMath.look(
      mood: TvAmbientMood.sport,
      seed: pitchSeed,
      evening: evening,
    );
    expect(cinema.peak.computeLuminance(),
        lessThan(evening.ambientPeak.computeLuminance()));
    expect(sport.peak.computeLuminance(),
        greaterThan(evening.ambientPeak.computeLuminance()));
    expect(sport.peak.computeLuminance(),
        lessThanOrEqualTo(TvAmbientMath.smpteCeiling));
    expect(cinema.peak.computeLuminance(),
        lessThan(sport.peak.computeLuminance()));
    // Plus chaud : moins de bleu par rapport au rouge.
    expect(
      cinema.peak.b / cinema.peak.r,
      lessThan(sport.peak.b / sport.peak.r),
    );
    expect(cinema.bg, isNot(const Color(0xFF000000)));
  });

  test('le guide prime sur le groupe quand il dit film ou sport', () {
    expect(
      TvAmbientMath.moodFor(ChannelGenre.news, 'Football'),
      TvAmbientMood.sport,
    );
    expect(
      TvAmbientMath.moodFor(ChannelGenre.news, 'Cinéma'),
      TvAmbientMood.cinema,
    );
    expect(
      TvAmbientMath.moodFor(ChannelGenre.sports, null),
      TvAmbientMood.sport,
    );
    expect(
      TvAmbientMath.moodFor(ChannelGenre.movies, ''),
      TvAmbientMood.cinema,
    );
    expect(
      TvAmbientMath.moodFor(ChannelGenre.news, 'météo'),
      TvAmbientMood.neutral,
    );
  });

  test('une image toute noire ne peint pas un halo noir', () {
    final Color seed = TvAmbientMath.averageRgb(<int>[0, 0, 0, 2, 2, 2]);
    final TvAmbientLook look = TvAmbientMath.look(
      mood: TvAmbientMood.cinema,
      seed: seed,
      evening: evening,
    );
    expect(look.peak.computeLuminance(), greaterThan(0));
    expect(look.peak, isNot(const Color(0xFF000000)));
  });

  test('le lecteur ne filtre pas l\'image pour le halo', () {
    final String player = File(
      'lib/features/tv/presentation/tv_player_screen.dart',
    ).readAsStringSync();
    expect(player, contains('color: Colors.black'));
    expect(player, isNot(contains('ColorFiltered')));
    expect(player, contains('TvAmbientDirector.instance.show'));
    expect(player, contains('TvAmbientDirector.instance.clear'));
  });
}
