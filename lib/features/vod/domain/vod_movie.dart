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

  // ----- Sérialisation (cache disque du catalogue, façon Netflix) -----
  //  Clés courtes : le catalogue peut compter 10 000+ films — chaque
  //  caractère économisé compte sur le fichier de cache.

  Map<String, dynamic> toJson() => <String, dynamic>{
        'i': id,
        'n': name,
        'c': category,
        'u': streamUrl,
        'e': containerExt,
        if (posterUrl != null) 'p': posterUrl,
        if (rating != null) 'r': rating,
        if (year != null) 'y': year,
      };

  factory VodMovie.fromJson(Map<String, dynamic> j) => VodMovie(
        id: j['i'] as String,
        name: j['n'] as String,
        category: (j['c'] as String?) ?? '',
        streamUrl: j['u'] as String,
        containerExt: (j['e'] as String?) ?? 'mp4',
        posterUrl: j['p'] as String?,
        rating: j['r'] as String?,
        year: j['y'] as String?,
      );
}
