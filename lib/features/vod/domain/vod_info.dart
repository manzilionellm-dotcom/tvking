// =========================================================
//  vod_info.dart — Fiche détaillée d'un film VOD (get_vod_info)
// =========================================================
//  Les MÉTADONNÉES RICHES d'un film (synopsis, casting, réalisateur,
//  genre, durée, image de fond…) renvoyées par l'appel Xtream
//  `get_vod_info`. Elles n'existent PAS dans `get_vod_streams` (le
//  catalogue) : on ne les récupère qu'à l'ouverture de la fiche.
//
//  POURQUOI tout est nullable et le parsing ultra-défensif : le
//  protocole Xtream n'est PAS normalisé. Selon le panel (XUI.one,
//  StreamCreed, forks maison…) un même champ peut être un int, une
//  String, une liste, absent, ou carrément mal typé. La règle ici est
//  la même que dans xtream_client.dart : on ne CRASH JAMAIS sur un
//  champ manquant — un champ illisible devient simplement `null` et
//  la fiche s'affiche avec ce qu'elle a (fail-open).
//
//  Les fonctions de parsing sont PURES et statiques → testables sans
//  réseau (cf. test/features/vod/vod_info_test.dart).
// =========================================================

import 'package:flutter/foundation.dart';

@immutable
class VodInfo {
  const VodInfo({
    this.plot,
    this.cast,
    this.director,
    this.genre,
    this.releaseDate,
    this.durationSecs,
    this.backdropUrl,
    this.tmdbId,
    this.youtubeTrailer,
    this.rating,
  });

  /// Synopsis (« plot » ou « description » selon les serveurs).
  final String? plot;

  /// Casting, une seule chaîne (ex. « Keanu Reeves, Carrie-Anne Moss »).
  final String? cast;

  /// Réalisateur(s).
  final String? director;

  /// Genre(s) (ex. « Action, Science-Fiction »).
  final String? genre;

  /// Date de sortie brute (ex. « 2019-05-14 » ou juste « 2019 »).
  final String? releaseDate;

  /// Durée du film en SECONDES (déjà normalisée depuis `duration_secs`
  /// ou depuis une durée « 01:47:33 » — cf. [parseDurationSecs]).
  final int? durationSecs;

  /// Image de FOND (paysage, ≠ affiche) pour la fiche plein écran.
  final String? backdropUrl;

  /// Identifiant TMDB éventuel (pour de futurs enrichissements).
  final String? tmdbId;

  /// Identifiant/URL YouTube de la bande-annonce, si fourni.
  final String? youtubeTrailer;

  /// Note (ex. « 7.4 ») — « 0 » et vide sont traités comme absents.
  final String? rating;

  /// Année de sortie (« 2019 »), extraite de [releaseDate] : premier
  /// groupe de 4 chiffres — tolère « 2019 », « 2019-05-14 », « 14/05/2019 ».
  String? get year {
    final String? d = releaseDate;
    if (d == null) return null;
    final RegExpMatch? m = RegExp(r'\d{4}').firstMatch(d);
    return m?.group(0);
  }

  // ============================================================
  //  Parsing (pur, défensif)
  // ============================================================

  /// Construit une fiche depuis la réponse COMPLÈTE de `get_vod_info`
  /// (ou `get_series_info` : mêmes clés dans le sous-objet `info`).
  ///
  /// Schémas rencontrés dans la nature :
  ///   { "info": { plot, cast, ... }, "movie_data": {...} }   ← standard
  ///   { plot, cast, ... }                                    ← à plat
  /// On lit d'abord le sous-objet `info`, puis la RACINE en repli.
  static VodInfo fromJson(Map<String, dynamic> json) {
    // `info` peut être une Map… ou n'importe quoi (liste vide quand le
    // film n'existe pas côté serveur !) → on ne caste jamais en aveugle.
    final Object? rawInfo = json['info'];
    final Map<String, dynamic> info =
        rawInfo is Map<String, dynamic> ? rawInfo : json;

    // Lecture avec REPLI racine : certains panels mettent la moitié des
    // champs dans `info` et l'autre à la racine.
    Object? pick(List<String> keys) {
      for (final String k in keys) {
        final Object? v = info[k];
        if (v != null) return v;
      }
      for (final String k in keys) {
        final Object? v = json[k];
        if (v != null) return v;
      }
      return null;
    }

    return VodInfo(
      plot: cleanString(pick(<String>['plot', 'description'])),
      cast: cleanString(pick(<String>['cast', 'actors'])),
      director: cleanString(pick(<String>['director'])),
      genre: cleanString(pick(<String>['genre'])),
      releaseDate: cleanString(
          pick(<String>['releasedate', 'release_date', 'releaseDate'])),
      durationSecs: parseDurationSecs(
        pick(<String>['duration_secs']),
        pick(<String>['duration']),
      ),
      backdropUrl: parseBackdrop(pick(<String>['backdrop_path', 'backdrop'])),
      tmdbId: cleanString(pick(<String>['tmdb_id', 'tmdb'])),
      youtubeTrailer: cleanString(pick(<String>['youtube_trailer', 'trailer'])),
      rating: cleanRating(pick(<String>['rating'])),
    );
  }

  /// Chaîne nettoyée : `null` si absent, vide, ou valeur « creuse »
  /// (les serveurs renvoient souvent "" ou "null" littéral).
  static String? cleanString(Object? raw) {
    if (raw == null) return null;
    final String s = raw.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return null;
    return s;
  }

  /// Note nettoyée : comme [cleanString], mais « 0 » = pas de note (même
  /// convention que le mapping du catalogue dans xtream_client.dart).
  static String? cleanRating(Object? raw) {
    final String? s = cleanString(raw);
    if (s == null || s == '0' || s == '0.0') return null;
    return s;
  }

  /// `backdrop_path` : selon les serveurs c'est une LISTE d'URLs, une
  /// String seule, ou n'importe quoi. On prend la première URL non vide.
  static String? parseBackdrop(Object? raw) {
    if (raw is List) {
      for (final Object? e in raw) {
        final String? s = cleanString(e);
        if (s != null) return s;
      }
      return null;
    }
    return cleanString(raw);
  }

  /// Durée en secondes, à partir de `duration_secs` (int OU String) avec
  /// repli sur `duration` au format horloge « 01:47:33 » (ou « 47:33 »).
  /// `null` si rien d'exploitable ou durée ≤ 0 (durée inconnue).
  static int? parseDurationSecs(Object? secsRaw, Object? clockRaw) {
    // 1) duration_secs : nombre direct, ou String contenant un nombre.
    if (secsRaw is num) {
      final int v = secsRaw.toInt();
      if (v > 0) return v;
    } else if (secsRaw != null) {
      final int? v = int.tryParse(secsRaw.toString().trim());
      if (v != null && v > 0) return v;
    }
    // 2) duration « HH:MM:SS » ou « MM:SS » : on additionne les segments
    //    de droite à gauche (secondes, minutes, heures).
    final String? clock = cleanString(clockRaw);
    if (clock == null) return null;
    final List<String> parts = clock.split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    int total = 0;
    for (final String p in parts) {
      final int? v = int.tryParse(p.trim());
      if (v == null || v < 0) return null; // segment illisible → on renonce
      total = total * 60 + v;
    }
    return total > 0 ? total : null;
  }

  /// « 1 h 47 min » ou « 47 min » — pour la ligne de métadonnées de la
  /// fiche (lisible à 3 m, pas un compteur « 01:47:33 »).
  static String formatDurationShort(int durationSecs) {
    final int mins = durationSecs ~/ 60;
    final int h = mins ~/ 60;
    final int m = mins % 60;
    if (h <= 0) return '$m min';
    return '$h h $m min';
  }

  /// « 42:15 » ou « 1:02:03 » — pour le bouton « Reprendre à … » (même
  /// format que le toast de reprise du lecteur).
  static String formatClock(Duration d) {
    final int s = d.inSeconds < 0 ? 0 : d.inSeconds;
    final int h = s ~/ 3600;
    final int m = (s % 3600) ~/ 60;
    final int sec = s % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
  }
}
