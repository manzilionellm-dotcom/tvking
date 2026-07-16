// =========================================================
//  m3u_vod_source.dart — Pont entre les entrées VOD d'un M3U et le Cinéma
// =========================================================
//  Une fois les entrées M3U classées (M3uVodClassifier, au parsing) et
//  relues depuis SQLite (PlaylistRepository.getVodChannels), ce module les
//  TRADUIT dans les modèles du Cinéma :
//
//    - Channel « film »    → VodMovie   (rejoint le catalogue Xtream)
//    - Channels « épisode »→ VodSeries + VodEpisode (regroupés par nom de
//                            série extrait de la numérotation SxxExx)
//
//  Fonctions PURES (pas de Flutter, pas d'E/S) : elles se testent
//  unitairement et peuvent tourner dans un isolate si le volume l'exige.
//
//  Conventions d'identifiants (IMPORTANT — reprise & épisode suivant) :
//    - film M3U     : id = external_id de la chaîne (ex. « m3u-3-421 ») —
//                     la reprise (PlaybackPositionRepository) accepte
//                     n'importe quelle clé stable ;
//    - épisode M3U  : id = « ep-<external_id> » — le préfixe « ep- » est LE
//                     contrat existant d'AutoplayPolicy (épisode suivant) ;
//    - série M3U    : id = « m3useries-<nom normalisé> » — reconnu par
//                     SeriesRepository.fetchDetail pour servir les épisodes
//                     depuis SQLite (zéro réseau).
// =========================================================

import '../../channels/domain/channel.dart';
import '../domain/m3u_vod_classifier.dart';
import '../domain/vod_movie.dart';
import '../domain/vod_series.dart';

/// Préfixe des identifiants de série issus d'un M3U.
const String kM3uSeriesIdPrefix = 'm3useries-';

/// Identifiant STABLE d'une série M3U : dérivé du seul nom (normalisé), pas
/// de l'ordre de la playlist → survit aux rafraîchissements de la source.
String m3uSeriesId(String seriesName) {
  final String norm = seriesName
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return '$kM3uSeriesIdPrefix${norm.isEmpty ? 'sans-nom' : norm}';
}

/// Extension du conteneur depuis l'URL (« …/123.mkv?tk=a » → « mkv »),
/// repli « mp4 » (sert au nom de fichier des téléchargements).
String m3uContainerExt(String url) {
  int end = url.indexOf('?');
  if (end < 0) end = url.indexOf('#');
  final String path = end < 0 ? url : url.substring(0, end);
  final int dot = path.lastIndexOf('.');
  final int slash = path.lastIndexOf('/');
  if (dot <= slash || dot == path.length - 1) return 'mp4';
  final String ext = path.substring(dot + 1).toLowerCase();
  return (ext.length > 5 || ext.isEmpty) ? 'mp4' : ext;
}

/// Traduit une chaîne M3U « film » en [VodMovie] du catalogue.
VodMovie m3uChannelToMovie(Channel c) => VodMovie(
      id: c.id,
      name: c.name,
      category: c.category,
      streamUrl: c.streamUrl,
      containerExt: m3uContainerExt(c.streamUrl),
      posterUrl: c.logoUrl,
    );

/// Sépare les entrées VOD d'un M3U en (films, épisodes) d'après le
/// classificateur — l'appelant fournit le résultat de getVodChannels.
({List<Channel> movies, List<Channel> episodes}) splitM3uVod(
    List<Channel> vod) {
  final List<Channel> movies = <Channel>[];
  final List<Channel> episodes = <Channel>[];
  for (final Channel c in vod) {
    switch (M3uVodClassifier.classify(url: c.streamUrl, name: c.name)) {
      case M3uVodKind.movie:
        movies.add(c);
      case M3uVodKind.episode:
        episodes.add(c);
      case M3uVodKind.live:
        break; // défensif — getVodChannels ne renvoie pas de live
    }
  }
  return (movies: movies, episodes: episodes);
}

/// Regroupe des chaînes « épisode » en séries (vignettes de catalogue).
/// Poster/catégorie = ceux du premier épisode rencontré (ordre playlist).
List<VodSeries> groupM3uEpisodesIntoSeries(List<Channel> episodes) {
  // LinkedHashMap implicite : préserve l'ordre d'apparition dans la source.
  final Map<String, VodSeries> bySeries = <String, VodSeries>{};
  final Map<String, int> counts = <String, int>{};
  for (final Channel c in episodes) {
    final M3uEpisodeTag? tag = M3uVodClassifier.episodeTag(c.name);
    final String name = tag?.seriesName ?? c.name;
    final String id = m3uSeriesId(name);
    counts[id] = (counts[id] ?? 0) + 1;
    bySeries.putIfAbsent(
      id,
      () => VodSeries(
        id: id,
        name: name,
        category: c.category,
        posterUrl: c.logoUrl,
      ),
    );
  }
  return bySeries.values.toList(growable: false);
}

/// Épisodes d'UNE série M3U ([seriesId] au format « m3useries-… »), triés
/// saison puis numéro. Sans numérotation lisible → S1, ordre d'apparition.
List<VodEpisode> m3uEpisodesForSeries(
    List<Channel> episodes, String seriesId) {
  final List<VodEpisode> out = <VodEpisode>[];
  int fallbackNum = 0;
  for (final Channel c in episodes) {
    final M3uEpisodeTag? tag = M3uVodClassifier.episodeTag(c.name);
    final String name = tag?.seriesName ?? c.name;
    if (m3uSeriesId(name) != seriesId) continue;
    fallbackNum++;
    out.add(VodEpisode(
      // « ep- » = contrat AutoplayPolicy (épisode suivant automatique).
      id: 'ep-${c.id}',
      title: c.name,
      season: tag?.season ?? 1,
      episodeNum: tag?.episode ?? fallbackNum,
      streamUrl: c.streamUrl,
      containerExt: m3uContainerExt(c.streamUrl),
      posterUrl: c.logoUrl,
    ));
  }
  out.sort((VodEpisode a, VodEpisode b) {
    final int s = a.season.compareTo(b.season);
    return s != 0 ? s : a.episodeNum.compareTo(b.episodeNum);
  });
  return out;
}
