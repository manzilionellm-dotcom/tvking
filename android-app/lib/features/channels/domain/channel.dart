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

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
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
  // Regex précompilées (appelé pour chaque logo manquant à l'écran).
  static final RegExp _rxDecor = RegExp(r'[#*=•‣◆◇■□●○▪▫]+');
  static final RegExp _rxWordSep = RegExp(r'[\s\-/+_|]+');

  String get initials {
    final String clean = name.replaceAll(_rxDecor, ' ');
    final List<String> words = clean
        .split(_rxWordSep)
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
  /// **Caché par identité et métadonnées** (comme [genre]/[country]/[quality]) : `curate()` est
  /// une passe de DIZAINES de RegExp. Sans ce cache, chaque accès la relançait —
  /// et le cache interne de `TitleCurator` (8000 entrées) THRASHE dès qu'une
  /// playlist dépasse 8000 chaînes (le cas réel : 50 000+), si bien que presque
  /// chaque appel ré-exécutait tout le pipeline. Conséquence mesurée (logcat
  /// SHIELD) : `_recompute` saturait le fil UI à 100 % pendant ~3,7 s → ANR
  /// (« Waited 5000ms for KeyEvent »). Mémoïsé par chaîne, c'est UNE curation
  /// par chaîne sur toute la session, puis O(1) — quelle que soit la taille.
  String get cleanName => _ChannelComputedCache.forChannel(this).cleanName ??=
      TitleCurator.curate(name);

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
  ChannelGenre get genre => _ChannelComputedCache.forChannel(this).genre ??=
      ChannelClassifier.classifyGenre(name, category);

  /// Un pays absent est aussi un résultat : ne pas relancer le classificateur.
  CountryInfo? get country {
    final _ChannelComputed entry = _ChannelComputedCache.forChannel(this);
    if (!entry.countryKnown) {
      entry.country = ChannelClassifier.detectCountry(name, category);
      entry.countryKnown = true;
    }
    return entry.country;
  }

  ChannelQuality get quality => _ChannelComputedCache.forChannel(this).quality ??=
      ChannelClassifier.detectQuality(name);

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

/// Un même identifiant peut changer de nom, de catégorie ou de playlist.
/// La clé décrit donc aussi les métadonnées classées. Une ancienne réponse
/// d'isolate ne peut plus attribuer son genre à une nouvelle chaîne.
typedef _ChannelCacheKey = (String, int?, String, String);

class _ChannelComputed {
  String? cleanName;
  ChannelGenre? genre;
  CountryInfo? country;
  bool countryKnown = false;
  ChannelQuality? quality;
}

abstract final class _ChannelComputedCache {
  static final Map<_ChannelCacheKey, _ChannelComputed> _entries =
      <_ChannelCacheKey, _ChannelComputed>{};
  // Accès répété au même objet : pas de tuple ni de recherche dans une grosse
  // Map à chaque rendu. L'Expando ne retient pas les anciennes chaînes en vie.
  static final Expando<_ChannelComputed> _attached = Expando<_ChannelComputed>();

  static _ChannelCacheKey _key(Channel c) => (c.id, c.playlistId, c.name, c.category);

  static _ChannelComputed? peek(Channel c) {
    final _ChannelComputed? attached = _attached[c];
    if (attached != null) return attached;
    final _ChannelComputed? shared = _entries[_key(c)];
    if (shared != null) _attached[c] = shared;
    return shared;
  }

  static _ChannelComputed forChannel(Channel c) => _attached[c] ??=
      _entries.putIfAbsent(_key(c), _ChannelComputed.new);

  /// Après un import/suppression, seuls les résultats encore utiles restent
  /// retenus globalement. Un ancien lecteur peut garder son propre objet
  /// jusqu'à sa fermeture, sans contaminer les métadonnées de la nouvelle liste.
  static void retain(List<Channel> channels) {
    final Set<_ChannelCacheKey> active = <_ChannelCacheKey>{
      for (final Channel channel in channels) _key(channel),
    };
    _entries.removeWhere((key, value) => !active.contains(key));
  }
}

// =========================================================
//  PRÉ-CALCUL EN ARRIÈRE-PLAN (performance, 25/09/2026)
// =========================================================
//  Le nettoyage des noms (TitleCurator, ~300 regex par nom) et la
//  classification (genre / pays / qualité, ~350 regex par chaîne) sont
//  mémoïsés par id, mais le PREMIER calcul restait sur le fil UI : sur une
//  grosse liste (30 000 chaînes), le premier `_recompute` de l'écran Direct
//  faisait ~10 millions de tests regex d'un coup → écran figé > 5 s → Android
//  tue l'app (« ça reste comme ça et ça se ferme »).
//
//  Ici, ce premier calcul se fait dans un ISOLATE (compute), par tranches,
//  et les résultats REMPLISSENT les mêmes caches. Le fil UI ne fait plus que
//  des lookups O(1). Les écrans qui ont besoin de TOUTES les valeurs
//  (Tendances, « Pour vous », Mode Enfants) attendent la fin du pré-calcul ;
//  les lignes visibles, elles, calculent leur nom à la demande (≈ 15 noms).
abstract final class ChannelPrecompute {
  static const int _kChunk = 2000;

  /// Vrai si les valeurs de [c] sont déjà en cache (nom curé + genre).
  static bool isDone(Channel c) {
    final _ChannelComputed? entry = _ChannelComputedCache.peek(c);
    return entry?.cleanName != null && entry?.genre != null;
  }

  /// Ces trois lectures ne déclenchent aucun classificateur sur le fil UI.
  static ChannelGenre? cachedGenre(Channel c) => _ChannelComputedCache.peek(c)?.genre;
  static String? cachedCleanName(Channel c) => _ChannelComputedCache.peek(c)?.cleanName;
  static ({bool known, CountryInfo? country}) cachedCountry(Channel c) {
    final _ChannelComputed? entry = _ChannelComputedCache.peek(c);
    return (known: entry?.countryKnown ?? false, country: entry?.country);
  }

  static void retainSnapshot(List<Channel> channels) => _ChannelComputedCache.retain(channels);

  @visibleForTesting
  static int get retainedEntryCount => _ChannelComputedCache._entries.length;

  /// Pré-calcule nom curé / genre / pays / qualité pour toutes les chaînes
  /// pas encore en cache, par tranches de [_kChunk] dans un isolate.
  /// [cancelled] est consulté entre deux tranches (écran fermé, nouvelle
  /// liste arrivée…). Ne throw jamais.
  static Future<void> run(List<Channel> channels,
      {bool Function()? cancelled}) async {
    final List<Channel> pending =
        channels.where((Channel c) => !isDone(c)).toList(growable: false);
    for (int i = 0; i < pending.length; i += _kChunk) {
      if (cancelled?.call() ?? false) return;
      final int end = (i + _kChunk < pending.length) ? i + _kChunk : pending.length;
      final List<List<String>> input = <List<String>>[
        for (final Channel c in pending.sublist(i, end))
          <String>[c.id, c.name, c.category],
      ];
      List<List<String>> out;
      try {
        out = await compute(_precomputeChunk, input);
      } catch (_) {
        return; // best-effort : les getters à la demande prennent le relais
      }
      // L'écran peut avoir disparu PENDANT compute, même dans le dernier lot.
      if (cancelled?.call() ?? false) return;
      for (int j = 0; j < out.length; j++) {
        final List<String> row = out[j];
        final _ChannelComputed entry = _ChannelComputedCache.forChannel(pending[i + j]);
        entry.cleanName ??= row[1];
        entry.genre ??= ChannelGenre.values[int.parse(row[2])];
        if (!entry.countryKnown) {
          entry.country = row[3].isEmpty ? null : ChannelClassifier.countryForKey(row[3]);
          entry.countryKnown = true;
        }
        entry.quality ??= ChannelQuality.values[int.parse(row[4])];
      }
    }
  }
}

/// Corps de l'isolate : uniquement des String en entrée/sortie (sérialisables).
/// Top-level = requis par `compute`.
List<List<String>> _precomputeChunk(List<List<String>> rows) {
  final List<List<String>> out = <List<String>>[];
  for (final List<String> r in rows) {
    final String id = r[0], name = r[1], category = r[2];
    out.add(<String>[
      id,
      TitleCurator.curate(name),
      ChannelClassifier.classifyGenre(name, category).index.toString(),
      ChannelClassifier.detectCountryKey(name, category) ?? '',
      ChannelClassifier.detectQuality(name).index.toString(),
    ]);
  }
  return out;
}
