// =========================================================
//  channel.dart — Modèle de données "Chaîne TV"
// =========================================================
//  Refonte Phase 1.4 :
//    - Suppression des dégradés aléatoires : la nouvelle UI
//      est centrée sur le LOGO, pas sur des cards colorées
//      arbitraires.
//    - Ajout de getters calculés (genre / pays / qualité)
//      qui exploitent `ChannelClassifier` pour permettre :
//         - les sections type Apple TV (Sports / Films / ...)
//         - les filtres par pays / qualité
//         - les badges "4K / HD" sur les vignettes
//
//  Classe immuable, constructeur const → optimisé pour les
//  rebuilds Flutter.
// =========================================================

import 'package:flutter/material.dart';

import 'channel_genre.dart';

// Re-export pour que les widgets qui importent `channel.dart`
// aient aussi accès à ChannelGenre / ChannelQuality / CountryInfo.
export 'channel_genre.dart';

@immutable
class Channel {
  const Channel({
    required this.id,
    required this.name,
    required this.category,
    required this.streamUrl,
    required this.isLive,
    this.playlistId,
    this.logoUrl,
    this.currentProgram,
    this.catchupSupported = false,
    this.catchupDays,
    this.catchupSource,
  });

  /// Identifiant unique de la chaîne (tvg-id côté M3U,
  /// stream_id côté Xtream, ou identifiant interne pour
  /// les chaînes fictives).
  final String id;

  /// Identifiant de la playlist d'origine (null pour les
  /// chaînes fictives de démo).
  final int? playlistId;

  /// Nom affiché (ex : "Canal+ Sport HD").
  final String name;

  /// Catégorie BRUTE telle qu'on l'a reçue dans la playlist
  /// (group-title M3U ou category_name Xtream). À nettoyer
  /// pour l'affichage via `ChannelClassifier.prettifyCategory`.
  final String category;

  /// URL du flux vidéo (HLS, MPEG-TS, MP4...).
  final String streamUrl;

  /// True si la chaîne diffuse actuellement en live.
  final bool isLive;

  /// URL distante du logo, si dispo dans la playlist.
  final String? logoUrl;

  /// Titre du programme en cours (rempli par l'EPG en Phase 2).
  final String? currentProgram;

  /// La chaîne supporte-t-elle le catch-up / replay ?
  final bool catchupSupported;

  /// Nombre de jours de catch-up disponibles.
  final int? catchupDays;

  /// Template d'URL catch-up (spec M3U).
  final String? catchupSource;

  // ============================================================
  //  Helpers de présentation
  // ============================================================

  /// Initiales (max 2 lettres) — pour le fallback quand pas
  /// de logo. On nettoie les décorations "##" / "**" qui
  /// polluent les playlists IPTV.
  String get initials {
    final String clean = name.replaceAll(RegExp(r'[#*=•‣◆◇■□●○▪▫]+'), ' ');
    final List<String> words = clean
        .split(RegExp(r'[\s\-/+_|]+'))
        .where((String w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final String w = words.first;
      return w.length >= 2
          ? w.substring(0, 2).toUpperCase()
          : w.substring(0, 1).toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  /// Nom propre, sans les décorations type "##" / "==" en début.
  String get cleanName {
    String s = name;
    s = s.replaceAll(RegExp(r'^[#*=•‣◆◇■□●○▪▫\s|/-]+'), '');
    s = s.replaceAll(RegExp(r'[#*=•‣◆◇■□●○▪▫]+\s*$'), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    s = s.trim();
    return s.isEmpty ? name : s;
  }

  /// Catégorie nettoyée pour l'affichage.
  String get prettyCategory => ChannelClassifier.prettifyCategory(category);

  /// Genre détecté (Sports, Films, Séries...) pour la classification
  /// dans les sections principales de l'app.
  ChannelGenre get genre => ChannelClassifier.classifyGenre(name, category);

  /// Pays détecté (null si on ne sait pas).
  CountryInfo? get country =>
      ChannelClassifier.detectCountry(name, category);

  /// Qualité détectée (HD, FHD, 4K, 8K).
  ChannelQuality get quality => ChannelClassifier.detectQuality(name);

  /// Indique si la chaîne a un logo distant utilisable.
  bool get hasLogo => logoUrl != null && logoUrl!.trim().isNotEmpty;

  // ============================================================
  //  Compat ascendante — pour les widgets qui n'ont pas encore
  //  été migrés vers ChannelLogo.
  // ============================================================

  /// Hérité de la v1 — gradient unique premium (or muted) servant
  /// uniquement de "skeleton" si jamais quelqu'un l'appelle.
  /// Le nouveau design n'utilise pas de gradient aléatoire.
  List<Color> get effectiveGradient => const <Color>[
        Color(0xFF1A1F26),
        Color(0xFF242B33),
      ];

  /// Pas de couleurs de marque arbitraires dans la v2.
  /// Le getter est conservé pour la compatibilité d'API.
  List<Color>? get gradientColors => null;
}
