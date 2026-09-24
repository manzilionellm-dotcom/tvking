// =========================================================
//  vod_movie.dart — Modèle d'un film VOD (vidéo à la demande)
// =========================================================
//  Un film servi par le serveur Xtream via `get_vod_streams`.
//  Contrairement à une chaîne live (flux continu), un film est un
//  FICHIER fini (mp4/mkv...) → on peut le lire en streaming OU le
//  télécharger pour le regarder hors-ligne (façon Netflix).
//
//  URL Xtream d'un film :
//    {server}/movie/{user}/{pass}/{stream_id}.{container_extension}
// =========================================================

import 'package:flutter/foundation.dart';

@immutable
class VodMovie {
  const VodMovie({
    required this.id,
    required this.name,
    required this.category,
    required this.streamUrl,
    required this.containerExt,
    this.posterUrl,
    this.rating,
    this.year,
  });

  /// Identifiant stable (ex. `vod-12345`).
  final String id;

  final String name;

  /// Catégorie (ex. « Action », « Comédie »…).
  final String category;

  /// URL directe du fichier film (streaming ou téléchargement).
  final String streamUrl;

  /// Extension du conteneur (mp4, mkv…). Sert au nom du fichier local.
  final String containerExt;

  /// Affiche/poster du film (TMDB-like, fourni par le serveur).
  final String? posterUrl;

  /// Note (ex. « 7.4 ») si fournie.
  final String? rating;

  /// Année de sortie si fournie.
  final String? year;
}
