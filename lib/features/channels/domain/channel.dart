// =========================================================
//  channel.dart — Modèle de données "Chaîne TV"
// =========================================================
//  Représente UNE chaîne dans l'app (peu importe d'où elle
//  vient : M3U, Xtream, en dur...). Toutes les couches qui
//  affichent une chaîne manipuleront cet objet.
//
//  Choix : classe immuable (tous les champs `final`) +
//  constructeur const. C'est la norme Flutter pour les
//  modèles, ça permet à Flutter d'optimiser les rebuilds.
// =========================================================

import 'package:flutter/material.dart';

/// Représente une chaîne de télévision.
@immutable
class Channel {
  const Channel({
    required this.id,
    required this.name,
    required this.category,
    required this.streamUrl,
    required this.isLive,
    this.logoUrl,
    this.gradientColors,
    this.currentProgram,
  });

  /// Identifiant unique (vient du tvg-id en M3U, ou stream_id en Xtream).
  final String id;

  /// Nom affiché de la chaîne (ex : "Canal+ Sport").
  final String name;

  /// Catégorie / groupe (ex : "Sport", "Cinéma", "Info").
  final String category;

  /// URL du flux vidéo (HLS, MPEG-TS, MP4...).
  /// En phase 1, on ne lance pas la lecture — c'est juste stocké.
  final String streamUrl;

  /// True si la chaîne diffuse actuellement (badge "EN DIRECT").
  final bool isLive;

  /// URL distante du logo. Si null → on affiche les initiales
  /// sur fond dégradé (cf. `gradientColors`).
  final String? logoUrl;

  /// Couleurs du dégradé de la vignette quand on n'a pas de logo.
  /// 2 couleurs minimum.
  final List<Color>? gradientColors;

  /// Titre du programme en cours (sera rempli par l'EPG en phase 2).
  final String? currentProgram;

  /// Initiales calculées à partir du nom (max 2 lettres).
  /// Exemple : "Canal+ Sport" → "CS".
  String get initials {
    final List<String> words = name
        .split(RegExp(r'\s+'))
        .where((String w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      return words.first.substring(0, 1).toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }
}
