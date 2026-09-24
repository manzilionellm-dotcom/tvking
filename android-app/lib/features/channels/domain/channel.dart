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

import '../../../core/curation/title_curator.dart';
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

  /// Nom propre, présentable à l'écran. Passe par le
  /// [TitleCurator] qui retire les préfixes IPTV (`FR |`,
  /// `ADULT:`), les suffixes techniques (`RAW`, `FHD`, `BACKUP`),
  /// les décorations (`★ ⚡ 🔥`) et applique un Title Case
  /// respectueux des acronymes (TF1, BBC, BFM…). Résultat : un
  /// nom digne d'une vraie plateforme premium, jamais d'IPTV
  /// brut affiché tel quel à l'utilisateur.
  ///
  /// Le `name` brut reste accessible via `name` directement —
  /// utile pour la recherche, l'EPG, le matching de favoris.
  ///
  /// **Caché par `id`** (comme [genre]/[country]/[quality]) : `curate()` est
  /// une passe de DIZAINES de RegExp. Sans ce cache, chaque accès la relançait —
  /// et le cache interne de `TitleCurator` (8000 entrées) THRASHE dès qu'une
  /// playlist dépasse 8000 chaînes (le cas réel : 50 000+), si bien que presque
  /// chaque appel ré-exécutait tout le pipeline. Conséquence mesurée (logcat
  /// SHIELD) : `_recompute` saturait le fil UI à 100 % pendant ~3,7 s → ANR
  /// (« Waited 5000ms for KeyEvent »). Mémoïsé par chaîne, c'est UNE curation
  /// par chaîne sur toute la session, puis O(1) — quelle que soit la taille.
  String get cleanName => _ChannelComputedCache.cleanNames.putIfAbsent(
        id,
        () => TitleCurator.curate(name),
      );

  /// Catégorie présentable à l'écran. Passe par le dictionnaire
  /// éditorial du [TitleCurator] (ex: "ADULT" → "After Dark",
  /// "MOVIES" → "Cinéma"), avec fallback sur le classifier
  /// historique si aucune entrée éditoriale n'est connue.
  String get prettyCategory {
    final String classifier = ChannelClassifier.prettifyCategory(category);
    return TitleCurator.curateCategory(classifier);
  }

  /// Genre détecté. **Caché** dans une Map statique car appelé
  /// à chaque rebuild sur 20 000+ chaînes — sans cache, les regex
  /// du classifier saturaient le main thread et l'UI laguait.
  ChannelGenre get genre => _ChannelComputedCache.genres.putIfAbsent(
        id,
        () => ChannelClassifier.classifyGenre(name, category),
      );

  /// Pays détecté (caché — voir [genre]).
  CountryInfo? get country => _ChannelComputedCache.countries.putIfAbsent(
        id,
        () => ChannelClassifier.detectCountry(name, category),
      );

  /// Qualité détectée (cachée — voir [genre]).
  ChannelQuality get quality => _ChannelComputedCache.qualities.putIfAbsent(
        id,
        () => ChannelClassifier.detectQuality(name),
      );

  /// Indique si la chaîne a un logo distant utilisable.
  bool get hasLogo => logoUrl != null && logoUrl!.trim().isNotEmpty;

  // ============================================================
  //  Compat ascendante — pour les widgets qui n'ont pas encore
  //  été migrés vers ChannelLogo.
  // ============================================================

  /// Hérité de la v1 — gradient unique LUMIÈRE (elevated → overcast)
  /// servant uniquement de "skeleton" si jamais quelqu'un l'appelle.
  /// Le design Maison Noir n'utilise pas de gradient aléatoire.
  List<Color> get effectiveGradient => const <Color>[
        Color(0xFF16121C), // surface.elevated
        Color(0xFF221D2D), // surface.overcast
      ];

  /// Pas de couleurs de marque arbitraires dans la v2.
  /// Le getter est conservé pour la compatibilité d'API.
  List<Color>? get gradientColors => null;
}

/// Cache statique pour les valeurs calculées (genre / pays / qualité).
///
/// Pourquoi : la classification (regex) est coûteuse. Sur 20 000
/// chaînes parcourues plusieurs fois par build (Home calcule 9
/// listes filtrées), on saturait le thread UI. Le cache mémoire
/// transforme 20 000 regex en 20 000 lookups O(1).
///
/// Limite : la Map vit pendant toute la session — ~50 octets par
/// chaîne soit ~1 Mo pour 20 000 entrées, négligeable.
abstract final class _ChannelComputedCache {
  static final Map<String, ChannelGenre> genres = <String, ChannelGenre>{};
  static final Map<String, CountryInfo?> countries = <String, CountryInfo?>{};
  static final Map<String, ChannelQuality> qualities =
      <String, ChannelQuality>{};
  // Nom curé (présentable) caché par id — voir Channel.cleanName.
  static final Map<String, String> cleanNames = <String, String>{};

  /// À appeler quand on supprime une playlist : on nettoie les
  /// entrées orphelines pour ne pas faire de fuite mémoire.
  static void invalidate(Iterable<String> idsToRemove) {
    for (final String id in idsToRemove) {
      genres.remove(id);
      countries.remove(id);
      qualities.remove(id);
      cleanNames.remove(id);
    }
  }
}
