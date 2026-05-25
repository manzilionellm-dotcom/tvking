// =========================================================
//  channel.dart — Modèle de données "Chaîne TV"
// =========================================================
//  Représente UNE chaîne dans l'app, peu importe l'origine :
//  M3U, Xtream Codes, ou (phase 1) données fictives.
//
//  Classe immuable, constructeur const → optimisé pour les
//  rebuilds Flutter.
//
//  Nouveauté Phase 1.1 :
//    - playlistId : à quelle playlist appartient la chaîne
//    - getter `effectiveGradient` : si la chaîne n'a pas de
//      `gradientColors` défini (cas standard d'une vraie
//      chaîne M3U), on en génère un automatiquement à partir
//      du nom, pour que l'UI reste belle même sans données.
// =========================================================

import 'package:flutter/material.dart';

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
    this.gradientColors,
    this.currentProgram,
    this.catchupSupported = false,
    this.catchupDays,
    this.catchupSource,
  });

  /// Identifiant unique de la chaîne (tvg-id côté M3U, stream_id
  /// côté Xtream, ou identifiant interne pour les chaînes fictives).
  final String id;

  /// Identifiant de la playlist d'origine (null pour les chaînes
  /// fictives de démo).
  final int? playlistId;

  /// Nom affiché (ex : "Canal+ Sport").
  final String name;

  /// Catégorie / groupe (ex : "Sport", "Cinéma").
  final String category;

  /// URL du flux vidéo (HLS, MPEG-TS, MP4...).
  final String streamUrl;

  /// True si la chaîne diffuse actuellement.
  final bool isLive;

  /// URL distante du logo, si dispo dans la playlist.
  final String? logoUrl;

  /// Couleurs forcées du dégradé (utilisé pour les chaînes
  /// de démo). Sinon, on génère automatiquement.
  final List<Color>? gradientColors;

  /// Titre du programme en cours (rempli par l'EPG en Phase 2).
  final String? currentProgram;

  /// La chaîne supporte-t-elle le catch-up / replay ?
  final bool catchupSupported;

  /// Nombre de jours de catch-up disponibles (souvent 1-7).
  final int? catchupDays;

  /// Template d'URL pour générer un lien catch-up (cf. spec M3U
  /// `catchup-source`). Phase 3 traitera ça.
  final String? catchupSource;

  // ============================================================
  //  Helpers de présentation
  // ============================================================

  /// Initiales calculées à partir du nom (max 2 lettres).
  String get initials {
    final List<String> words = name
        .split(RegExp(r'[\s\-/+_]+'))
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

  /// Couleurs du dégradé à utiliser pour la vignette :
  /// soit celles forcées, soit générées depuis le nom.
  List<Color> get effectiveGradient {
    if (gradientColors != null && gradientColors!.isNotEmpty) {
      return gradientColors!;
    }
    return _generateGradient(id.isNotEmpty ? id : name);
  }
}

// ==============================================================
//  Génération automatique de gradient — déterministe.
// ==============================================================
//  L'idée : à partir d'une chaîne d'identifiant (id ou nom),
//  on calcule un hash, on en tire deux teintes HSL "premium"
//  qui vont bien ensemble.
//
//  Avantage : la même chaîne aura TOUJOURS le même gradient
//  d'un lancement à l'autre — pas de zapping visuel chelou.
// ==============================================================

const List<List<Color>> _kPremiumGradientPalette = <List<Color>>[
  <Color>[Color(0xFFFF3366), Color(0xFF7B1FA2)], // rose → violet
  <Color>[Color(0xFF00D9FF), Color(0xFF0288D1)], // cyan → bleu
  <Color>[Color(0xFFFFD700), Color(0xFFFF6F00)], // or → orange
  <Color>[Color(0xFF00E676), Color(0xFF00BFA5)], // vert → teal
  <Color>[Color(0xFFE040FB), Color(0xFF7C4DFF)], // magenta → indigo
  <Color>[Color(0xFF455A64), Color(0xFF263238)], // gris-bleu sombre
  <Color>[Color(0xFF8D6E63), Color(0xFF4E342E)], // brun chaud
  <Color>[Color(0xFFD32F2F), Color(0xFF212121)], // rouge → noir
  <Color>[Color(0xFFFFEB3B), Color(0xFFFF6F00)], // jaune → orange
  <Color>[Color(0xFF26C6DA), Color(0xFF00838F)], // turquoise → teal foncé
  <Color>[Color(0xFFAD1457), Color(0xFF6A1B9A)], // bordeaux → pourpre
  <Color>[Color(0xFF1976D2), Color(0xFF0D47A1)], // bleu vif → marine
  <Color>[Color(0xFF388E3C), Color(0xFF1B5E20)], // vert sapin
  <Color>[Color(0xFFF57C00), Color(0xFFE65100)], // orange brûlé
];

List<Color> _generateGradient(String seed) {
  final int hash = seed.hashCode.abs();
  final int index = hash % _kPremiumGradientPalette.length;
  return _kPremiumGradientPalette[index];
}
