// Rangées du panel tirées uniquement de la liste déjà importée. Le classement
// réutilise celui du Direct ; aucun flux n'est ouvert ni ajouté. Pour les grosses
// listes, les mots-clés sont analysés dans un isolate, jamais pendant build().
import 'package:flutter/foundation.dart';

import '../../channels/domain/channel.dart';
import '../../simple_home/data/home_layout_repository.dart';
import 'home_shelves.dart';

const List<String> kTvGenreHomeSections = <String>[
  HomeSectionKey.sport,
  HomeSectionKey.entertainment,
  HomeSectionKey.info,
  HomeSectionKey.kids,
  HomeSectionKey.general,
  HomeSectionKey.cinema,
];

String? tvHomeSectionForGenre(ChannelGenre genre) => switch (genre) {
      ChannelGenre.sports => HomeSectionKey.sport,
      ChannelGenre.entertainment ||
      ChannelGenre.series ||
      ChannelGenre.music ||
      ChannelGenre.documentary =>
        HomeSectionKey.entertainment,
      ChannelGenre.news => HomeSectionKey.info,
      ChannelGenre.kids => HomeSectionKey.kids,
      ChannelGenre.international ||
      ChannelGenre.other =>
        HomeSectionKey.general,
      ChannelGenre.movies => HomeSectionKey.cinema,
      // L'accueil n'expose jamais d'aperçu adulte. Le Direct conserve son verrou.
      ChannelGenre.adult => null,
    };

/// Données sérialisables pour compute : id, nom, groupe. « Cinéma » désigne ici
/// les chaînes de cinéma en direct, pas le catalogue ni les reprises VOD.
Map<String, List<String>> tvGenreShelfIds(List<List<String>> rows) {
  final result = <String, List<String>>{};
  final seen = <String>{};
  for (final row in rows) {
    if (row.length != 3 || !seen.add(row[0])) continue;
    final key =
        tvHomeSectionForGenre(ChannelClassifier.classifyGenre(row[1], row[2]));
    if (key == null) continue;
    final ids = result.putIfAbsent(key, () => <String>[]);
    if (ids.length < kHomeShelfMax) ids.add(row[0]);
    if (result.length == kTvGenreHomeSections.length &&
        result.values.every((ids) => ids.length >= kHomeShelfMax)) {
      break;
    }
  }
  return result;
}

Future<Map<String, List<Channel>>> tvGenreShelves(
    List<Channel> channels) async {
  if (channels.isEmpty) return const <String, List<Channel>>{};
  // Même occurrence pour le classement et la carte : un identifiant dupliqué
  // plus loin (VOD ou adulte) ne doit jamais remplacer une chaîne déjà retenue.
  final byId = <String, Channel>{};
  for (final channel in channels) {
    if (channel.isLive) byId.putIfAbsent(channel.id, () => channel);
  }
  final rows = <List<String>>[
    for (final channel in byId.values)
      <String>[channel.id, channel.name, channel.category],
  ];
  final ids = rows.length > 500
      ? await compute(tvGenreShelfIds, rows)
      : tvGenreShelfIds(rows);
  return <String, List<Channel>>{
    for (final entry in ids.entries)
      entry.key: <Channel>[
        for (final id in entry.value)
          if (byId[id] case final channel?) channel
      ],
  };
}
