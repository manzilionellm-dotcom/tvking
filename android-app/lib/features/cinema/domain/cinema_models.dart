// =========================================================
//  cinema_models.dart — Modèles du module Cinéma (Films + Séries)
// =========================================================
//  Tout vient du (ou des) compte(s) Xtream du client — jamais d'URL en dur.
//
//  API Xtream utilisée (player_api.php) :
//    • get_vod_categories / get_vod_streams[&category_id]      → films
//    • get_vod_info&vod_id                                     → fiche film
//    • get_series_categories / get_series[&category_id]        → séries
//    • get_series_info&series_id                               → saisons/épisodes
//  URLs de lecture (format standard Xtream) :
//    • film    : {serveur}/movie/{user}/{pass}/{stream_id}.{ext}
//    • épisode : {serveur}/series/{user}/{pass}/{episode_id}.{ext}
//
//  Ces classes sont PURES (aucun widget) et envoyables entre isolates : le
//  décodage JSON et la construction des objets se font HORS du fil UI.
// =========================================================
import 'package:flutter/foundation.dart';

/// Films ou séries.
enum CinemaKind { movie, series }

/// Un compte Xtream du client (le module fusionne TOUS ses comptes, comme le
/// Direct fusionne toutes ses listes).
@immutable
class CinemaSource {
  const CinemaSource({
    required this.key,
    required this.playlistId,
    required this.server,
    required this.username,
    required this.password,
  });

  /// Clé courte et stable (`p<playlistId>`), préfixe des identifiants.
  final String key;
  final int playlistId;

  /// Base du serveur SANS slash final.
  final String server;
  final String username;
  final String password;

  String movieUrl(String streamId, String ext) =>
      '$server/movie/$username/$password/$streamId.$ext';

  String episodeUrl(String episodeId, String ext) =>
      '$server/series/$username/$password/$episodeId.$ext';
}

/// Une catégorie d'un compte (id serveur).
@immutable
class CategoryRef {
  const CategoryRef(this.sourceKey, this.categoryId);
  final String sourceKey;
  final String categoryId;
}

/// Catégorie AFFICHÉE : les catégories de même nom sur plusieurs comptes sont
/// FUSIONNÉES (une seule ligne « Action » même avec 3 comptes).
@immutable
class CinemaCategory {
  const CinemaCategory({
    required this.key,
    required this.name,
    required this.parts,
    this.languageKey,
    this.isAdult = false,
    this.isKids = false,
  });

  /// Nom normalisé (clé de fusion).
  final String key;

  /// Libellé nettoyé pour l'affichage.
  final String name;

  /// Les catégories serveur réunies sous ce libellé.
  final List<CategoryRef> parts;

  /// Langue déduite du nom (`fr`, `en`, `zh`…) — `null` si rien d'évident.
  final String? languageKey;

  /// Contenu adulte (verrouillé par le code parental).
  final bool isAdult;

  /// Contenu enfants (seul visible en Mode Enfants).
  final bool isKids;
}

/// Un film ou une série dans une liste (vignette).
@immutable
class CinemaTitle {
  const CinemaTitle({
    required this.id,
    required this.kind,
    required this.sourceKey,
    required this.remoteId,
    required this.name,
    required this.categoryKey,
    required this.searchKey,
    this.posterUrl,
    this.rating,
    this.year,
    this.addedAt = 0,
    this.containerExt = 'mp4',
    this.streamUrl,
    this.plot,
  });

  /// Identifiant unique toutes sources confondues (`p3:m:12345`).
  final String id;
  final CinemaKind kind;
  final String sourceKey;

  /// `stream_id` (film) ou `series_id` (série) côté serveur.
  final String remoteId;
  final String name;

  /// Clé de la [CinemaCategory] d'origine.
  final String categoryKey;

  /// Nom normalisé (minuscules, sans accents) pour la recherche.
  final String searchKey;
  final String? posterUrl;

  /// Note sur 10 (null si absente / nulle).
  final double? rating;

  /// Année (« 2021 ») si fournie ou lisible dans le nom.
  final String? year;

  /// Date d'ajout sur le serveur (secondes epoch) → « Récemment ajoutés ».
  final int addedAt;

  /// Films : extension du fichier (mp4, mkv…).
  final String containerExt;

  /// Films : URL de lecture directe. Séries : null (on lit des épisodes).
  final String? streamUrl;

  /// Résumé (souvent fourni dans la liste des séries).
  final String? plot;
}

/// Fiche détaillée (film ou série).
@immutable
class CinemaDetails {
  const CinemaDetails({
    this.plot,
    this.cast,
    this.director,
    this.genre,
    this.releaseDate,
    this.durationSec = 0,
    this.backdropUrl,
    this.posterUrl,
    this.rating,
  });

  final String? plot;
  final String? cast;
  final String? director;
  final String? genre;
  final String? releaseDate;
  final int durationSec;
  final String? backdropUrl;
  final String? posterUrl;
  final double? rating;

  static const CinemaDetails empty = CinemaDetails();
}

/// Une saison.
@immutable
class CinemaSeason {
  const CinemaSeason({
    required this.number,
    required this.name,
    this.coverUrl,
    this.episodeCount = 0,
  });
  final int number;
  final String name;
  final String? coverUrl;
  final int episodeCount;
}

/// Un épisode (lisible et téléchargeable comme un film).
@immutable
class CinemaEpisode {
  const CinemaEpisode({
    required this.id,
    required this.remoteId,
    required this.seriesId,
    required this.season,
    required this.number,
    required this.title,
    required this.streamUrl,
    required this.containerExt,
    this.plot,
    this.durationSec = 0,
    this.stillUrl,
  });

  /// Identifiant unique (`p3:e:98765`).
  final String id;
  final String remoteId;

  /// [CinemaTitle.id] de la série.
  final String seriesId;
  final int season;
  final int number;
  final String title;
  final String streamUrl;
  final String containerExt;
  final String? plot;
  final int durationSec;
  final String? stillUrl;
}

/// Fiche série complète : infos + saisons + épisodes (triés).
@immutable
class SeriesDetails {
  const SeriesDetails({
    required this.details,
    required this.seasons,
    required this.episodes,
  });

  final CinemaDetails details;
  final List<CinemaSeason> seasons;

  /// Épisodes par numéro de saison, triés par numéro d'épisode.
  final Map<int, List<CinemaEpisode>> episodes;

  /// Épisode SUIVANT (même saison, sinon 1er de la saison suivante).
  CinemaEpisode? nextAfter(CinemaEpisode e) {
    final List<int> order = seasons.map((CinemaSeason s) => s.number).toList();
    final List<CinemaEpisode> same = episodes[e.season] ?? const <CinemaEpisode>[];
    final int i = same.indexWhere((CinemaEpisode x) => x.id == e.id);
    if (i >= 0 && i + 1 < same.length) return same[i + 1];
    final int si = order.indexOf(e.season);
    for (int k = si + 1; k >= 1 && k < order.length; k++) {
      final List<CinemaEpisode> next = episodes[order[k]] ?? const <CinemaEpisode>[];
      if (next.isNotEmpty) return next.first;
    }
    return null;
  }

  /// Tous les épisodes dans l'ordre de visionnage.
  List<CinemaEpisode> get allInOrder => <CinemaEpisode>[
        for (final CinemaSeason s in seasons)
          ...(episodes[s.number] ?? const <CinemaEpisode>[]),
      ];
}
