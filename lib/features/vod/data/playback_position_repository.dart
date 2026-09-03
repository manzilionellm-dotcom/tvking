// =========================================================
//  playback_position_repository.dart — Reprise de lecture (VOD, TV)
// =========================================================
//  La VRAIE reprise façon Netflix (« Reprendre à 42:15 ») : mémorise OÙ
//  l'utilisateur s'est arrêté dans un film / un épisode, pour que le lecteur
//  reprenne directement à cette position au lieu de rejouer depuis le début.
//
//  CLÉ PAR CONTENU : l'id du Channel poussé au lecteur, c'est-à-dire l'id
//  Xtream stable (`vod-12345` pour un film, `ep-678` pour un épisode). PAS
//  l'URL du flux : elle change quand le film est téléchargé hors-ligne
//  (file://) ou si les identifiants du compte tournent — l'id, lui, survit.
//
//  RÈGLES MÉTIER (celles de Netflix, calquées) :
//    • position < 60 s        → on ne sauve RIEN (zapping d'essai, générique) ;
//    • position > 95 % du film → TERMINÉ : on SUPPRIME l'entrée (pas de
//      « Reprendre à 1:58:57 » sur un film fini — on le considère vu) ;
//    • entre les deux         → on mémorise position + durée + métadonnées.
//
//  Stockage : SharedPreferences (liste JSON locale, comme RecentVodRepository
//  et VodWatchlistRepository), clé SUFFIXÉE par profil. BORNÉ à 100 entrées,
//  éviction des plus anciennes (anti-OOM et anti-bloat prefs : ~30 Ko max).
//  ChangeNotifier : les rangées « Continuer à regarder » se rafraîchissent
//  toutes seules quand une position change. AUCUN lien avec le moteur vidéo.
// =========================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/profiles/profiles_repository.dart';
import 'family_position_sync.dart';

/// Une position de lecture mémorisée : où en est l'utilisateur dans CE
/// contenu, plus les métadonnées minimales pour l'afficher dans une rangée
/// « Continuer à regarder » et RELANCER la lecture sans repasser par le
/// catalogue (nom, affiche, URL du flux, film ou épisode).
@immutable
class PlaybackPosition {
  const PlaybackPosition({
    required this.key,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
    required this.name,
    required this.streamUrl,
    this.posterUrl,
    this.isEpisode = false,
  });

  /// Clé stable du contenu = id du Channel (`vod-…` film, `ep-…` épisode).
  final String key;

  /// Position de lecture sauvegardée (millisecondes).
  final int positionMs;

  /// Durée totale du média (millisecondes). Toujours > 0 : on ne sauvegarde
  /// jamais sans durée connue (impossible d'appliquer la règle des 95 %,
  /// ni de dessiner une barre de progression honnête).
  final int durationMs;

  /// Dernière mise à jour — sert à l'ordre (plus récent d'abord) et à
  /// l'éviction (les plus anciens sautent quand on dépasse le plafond).
  final DateTime updatedAt;

  /// Nom affichable (titre du film, ou « S1 E3 · Titre » pour un épisode).
  final String name;

  /// URL du flux au moment de la sauvegarde — de quoi relancer la lecture
  /// directement depuis la rangée « Continuer à regarder ».
  final String streamUrl;

  /// Affiche/poster (pour la vignette de la rangée).
  final String? posterUrl;

  /// `true` = épisode de série, `false` = film.
  final bool isEpisode;

  /// Fraction déjà vue (0..1) — pour la petite barre dorée sous l'affiche.
  double get progress =>
      durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

  /// Position sous forme de [Duration] (confort pour le lecteur).
  Duration get position => Duration(milliseconds: positionMs);
}

class PlaybackPositionRepository extends ChangeNotifier {
  PlaybackPositionRepository._();
  static final PlaybackPositionRepository instance =
      PlaybackPositionRepository._();

  static const String _baseKey = 'tv_playback_positions';

  /// Clé PAR PROFIL (suffixe vide pour « Famille » → données conservées).
  String get _key => '$_baseKey${ProfilesRepository.instance.keySuffix}';

  /// Plafond d'entrées : assez pour toute une famille de gros regardeurs,
  /// assez petit pour que prefs reste léger (~30 Ko) — anti-bloat/anti-OOM.
  static const int _max = 100;

  /// En-deçà, on ne sauve rien : l'utilisateur a juste « goûté » le film
  /// (générique, mauvais choix). Reprendre à 0:45 n'apporte rien.
  static const Duration minPosition = Duration(seconds: 60);

  /// Au-delà de cette fraction, le contenu est considéré TERMINÉ : on
  /// supprime l'entrée (il ne reste que le générique de fin).
  static const double finishedRatio = 0.95;

  /// Entrées en mémoire, TOUJOURS triées du plus récent au plus ancien
  /// (l'invariant est maintenu à chaque mutation → `entries` est O(1)).
  List<PlaybackPosition> _items = <PlaybackPosition>[];
  bool _loaded = false;

  /// Positions RELANÇABLES, de la plus récente à la plus ancienne — l'ordre
  /// exact d'une rangée « Continuer à regarder ». Une position reçue de la
  /// famille sans URL locale (contenu jamais ouvert sur CET appareil) n'y
  /// figure pas : rien à relancer d'un clic. Sa reprise et sa barre de
  /// progression, elles, marchent (cf. [positionFor], [progressFor]).
  List<PlaybackPosition> get entries => List<PlaybackPosition>.unmodifiable(
      _items.where((PlaybackPosition e) => e.streamUrl.isNotEmpty));

  /// TOUTES les positions, URL locale ou non (synchro famille, tests).
  List<PlaybackPosition> get allEntries =>
      List<PlaybackPosition>.unmodifiable(_items);

  /// Charge les positions depuis le disque. Branché au démarrage (main_tv) ;
  /// best-effort : une entrée corrompue ne casse jamais l'app.
  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> raw = prefs.getStringList(_key) ?? <String>[];
      _items = raw.map(_decode).whereType<PlaybackPosition>().toList()
        ..sort((PlaybackPosition a, PlaybackPosition b) =>
            b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      debugPrint('[PlaybackPos] load: $e');
      _items = <PlaybackPosition>[];
    }
    _loaded = true;
    notifyListeners();
    // FAMILLE : les positions du profil actif poussées depuis les autres
    // appareils. Non bloquant ; sans réseau, on garde le local.
    unawaited(FamilyPositionSync.instance.pullNow());
  }

  /// FUSION des positions reçues de la famille : « le plus récent gagne ».
  /// Une entrée distante plus récente remplace la locale mais GARDE l'URL de
  /// flux locale (le serveur n'en stocke jamais). [finished] : contenus
  /// terminés ailleurs → retirés ici s'ils sont plus anciens. Renvoie le
  /// nombre d'entrées modifiées. Aucun renvoi vers le serveur (pas de boucle).
  Future<int> mergeRemote(
    List<PlaybackPosition> remote, {
    Map<String, DateTime> finished = const <String, DateTime>{},
  }) async {
    int changed = 0;
    for (final PlaybackPosition r in remote) {
      final PlaybackPosition? local = entryFor(r.key);
      if (local != null && !r.updatedAt.isAfter(local.updatedAt)) continue;
      final DateTime? gone = finished[r.key];
      if (gone != null && gone.isAfter(r.updatedAt)) continue;
      _items.removeWhere((PlaybackPosition e) => e.key == r.key);
      _items.add(PlaybackPosition(
        key: r.key,
        positionMs: r.positionMs,
        durationMs: r.durationMs,
        updatedAt: r.updatedAt,
        name: r.name.isNotEmpty ? r.name : (local?.name ?? ''),
        streamUrl: local?.streamUrl ?? r.streamUrl,
        posterUrl: r.posterUrl ?? local?.posterUrl,
        isEpisode: r.isEpisode,
      ));
      changed++;
    }
    for (final MapEntry<String, DateTime> f in finished.entries) {
      final PlaybackPosition? local = entryFor(f.key);
      if (local == null || !f.value.isAfter(local.updatedAt)) continue;
      _items.removeWhere((PlaybackPosition e) => e.key == f.key);
      changed++;
    }
    if (changed == 0) return 0;
    _items.sort((PlaybackPosition a, PlaybackPosition b) =>
        b.updatedAt.compareTo(a.updatedAt));
    if (_items.length > _max) _items = _items.sublist(0, _max);
    await _save(notifyFamily: false);
    return changed;
  }

  /// Charge UNE seule fois (appels suivants = no-op). Filet de sécurité pour
  /// le lecteur : même si le `load()` du démarrage n'a pas encore tourné, la
  /// reprise fonctionne (lecture prefs en quelques ms, bien avant que le flux
  /// soit prêt à seek).
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    await load();
  }

  /// Mémorise la position courante d'un contenu, en appliquant les règles
  /// métier (< 60 s → rien ; > 95 % → terminé, entrée supprimée).
  ///
  /// [at] : horloge injectable pour les TESTS uniquement (ordre/éviction
  /// déterministes) — en production, laisser `null` (= DateTime.now()).
  Future<void> record({
    required String key,
    required Duration position,
    required Duration duration,
    required String name,
    required String streamUrl,
    String? posterUrl,
    bool isEpisode = false,
    DateTime? at,
  }) async {
    // Durée inconnue → impossible d'appliquer la règle des 95 % ni de
    // dessiner une barre honnête : on ne sauve rien (cas direct/erreur).
    if (duration <= Duration.zero) return;
    // Trop tôt : simple zapping d'essai, on ne pollue pas la liste. On ne
    // TOUCHE PAS non plus à une éventuelle entrée existante : revoir 30 s
    // d'un film ne doit pas effacer un vrai point de reprise à 42:15.
    if (position < minPosition) return;
    // Quasiment fini → TERMINÉ : plus rien à reprendre.
    if (position.inMilliseconds > duration.inMilliseconds * finishedRatio) {
      await markFinished(key);
      return;
    }
    _items.removeWhere((PlaybackPosition e) => e.key == key);
    _items.insert(
      0,
      PlaybackPosition(
        key: key,
        positionMs: position.inMilliseconds,
        durationMs: duration.inMilliseconds,
        updatedAt: at ?? DateTime.now(),
        name: name,
        streamUrl: streamUrl,
        posterUrl: posterUrl,
        isEpisode: isEpisode,
      ),
    );
    // L'insertion en tête suffit en production (now() est croissant) ; le tri
    // re-garantit l'invariant même avec une horloge de test arbitraire.
    _items.sort((PlaybackPosition a, PlaybackPosition b) =>
        b.updatedAt.compareTo(a.updatedAt));
    // Éviction bornée : la liste est triée → les plus anciens sont en queue.
    if (_items.length > _max) _items = _items.sublist(0, _max);
    await _save();
  }

  /// Entrée complète pour [key] (null si rien à reprendre).
  PlaybackPosition? entryFor(String key) {
    for (final PlaybackPosition e in _items) {
      if (e.key == key) return e;
    }
    return null;
  }

  /// Position à laquelle reprendre [key] — null si rien de mémorisé (jamais
  /// vu, trop tôt arrêté, ou déjà terminé).
  Duration? positionFor(String key) => entryFor(key)?.position;

  /// Fraction déjà vue (0..1) pour la barre de progression sous l'affiche —
  /// null si aucune position mémorisée pour [key].
  double? progressFor(String key) => entryFor(key)?.progress;

  /// Marque [key] TERMINÉ : on oublie sa position (le contenu ne doit plus
  /// apparaître dans « Continuer à regarder »).
  Future<void> markFinished(String key) async {
    final int before = _items.length;
    _items.removeWhere((PlaybackPosition e) => e.key == key);
    if (_items.length == before) return; // rien à faire → pas d'I/O inutile
    // Famille : « terminé » ici doit disparaître aussi sur les autres
    // appareils (tombstone poussée avec le prochain envoi).
    FamilyPositionSync.instance.noteFinished(key);
    await _save(notifyFamily: false);
  }

  /// Remise à zéro COMPLÈTE pour les tests (le singleton survit d'un test à
  /// l'autre — sans ça, l'état fuirait entre les cas).
  @visibleForTesting
  void resetForTest() {
    _items = <PlaybackPosition>[];
    _loaded = false;
  }

  Future<void> _save({bool notifyFamily = true}) async {
    notifyListeners();
    // Famille : envoi DIFFÉRÉ vers les autres appareils (jamais depuis une
    // fusion reçue, sinon boucle serveur ↔ app).
    if (notifyFamily) FamilyPositionSync.instance.noteChanged();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          _key, _items.map(_encode).toList(growable: false));
    } catch (e) {
      debugPrint('[PlaybackPos] save: $e');
    }
  }

  String _encode(PlaybackPosition e) => jsonEncode(<String, Object?>{
        'key': e.key,
        'positionMs': e.positionMs,
        'durationMs': e.durationMs,
        'updatedAt': e.updatedAt.millisecondsSinceEpoch,
        'name': e.name,
        'streamUrl': e.streamUrl,
        'posterUrl': e.posterUrl,
        'isEpisode': e.isEpisode,
      });

  PlaybackPosition? _decode(String s) {
    try {
      final Map<String, dynamic> j = jsonDecode(s) as Map<String, dynamic>;
      return PlaybackPosition(
        key: j['key'] as String,
        positionMs: j['positionMs'] as int,
        durationMs: j['durationMs'] as int,
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(j['updatedAt'] as int),
        name: (j['name'] as String?) ?? '',
        streamUrl: j['streamUrl'] as String,
        posterUrl: j['posterUrl'] as String?,
        isEpisode: (j['isEpisode'] as bool?) ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}
