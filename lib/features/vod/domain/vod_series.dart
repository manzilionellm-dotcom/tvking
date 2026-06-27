// =========================================================
//  vod_series.dart — Modèles Séries (VOD) Xtream
// =========================================================
//  Une SÉRIE (get_series) regroupe des SAISONS, chacune contenant des
//  ÉPISODES (get_series_info). Contrairement à un film, on ne connaît les
//  épisodes qu'APRÈS avoir ouvert la fiche série (2e appel réseau).
//
//  URL d'un épisode (format standard Xtream) :
//    {server}/series/{user}/{pass}/{episode_id}.{container_extension}
// =========================================================

import 'package:flutter/foundation.dart';

/// Une série (vignette du catalogue), avant chargement des épisodes.
@immutable
class VodSeries {
  const VodSeries({
    required this.id,
    required this.name,
    required this.category,
    this.posterUrl,
    this.plot,
    this.rating,
    this.year,
  });

  /// Identifiant série Xtream (series_id) — utilisé pour get_series_info.
  final String id;
  final String name;
  final String category;
  final String? posterUrl;
  final String? plot;
  final String? rating;
  final String? year;
}

/// Un épisode jouable (déjà résolu en URL de fichier).
@immutable
class VodEpisode {
  const VodEpisode({
    required this.id,
    required this.title,
    required this.season,
    required this.episodeNum,
    required this.streamUrl,
    required this.containerExt,
    this.posterUrl,
  });

  final String id;
  final String title;
  final int season;
  final int episodeNum;
  final String streamUrl;
  final String containerExt;
  final String? posterUrl;

  /// Libellé court « S01E03 ».
  String get tag =>
      'S${season.toString().padLeft(2, '0')}E${episodeNum.toString().padLeft(2, '0')}';
}
