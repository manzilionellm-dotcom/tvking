// =========================================================
//  followed_matches_service.dart — Les matchs que LE CLIENT choisit
// =========================================================
//  Demande propriétaire (23/08) : « quelqu'un peut choisir les matchs
//  où il veut suivre ».
//
//  Jusqu'ici, on ne pouvait suivre que des ÉQUIPES : mettre le Real en
//  favori, et recevoir tous ses matchs. C'est trop grossier. Quelqu'un
//  veut suivre LA finale, LE derby, LE Grand Prix de dimanche — sans
//  s'abonner à tout le reste de la saison.
//
//  Ce service tient donc une liste de MATCHS choisis un par un.
//
//  CE QU'IL STOCKE, ET POURQUOI : pas seulement l'identifiant, mais un
//  résumé du match (noms, date, sport). Sans ça, l'écran « mes matchs
//  suivis » serait vide tant que le réseau n'a pas répondu — et
//  totalement vide en avion. Le résumé est minuscule (quelques centaines
//  d'octets par match) et rend l'écran instantané, hors ligne compris.
//
//  MÉNAGE AUTOMATIQUE : un match vieux de plus de deux jours est oublié.
//  Sans cette purge, la liste enflerait indéfiniment et le client verrait
//  s'accumuler des rencontres jouées il y a des mois.
// =========================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/sport_models.dart';

class FollowedMatchesService {
  FollowedMatchesService._();
  static final FollowedMatchesService instance = FollowedMatchesService._();

  static const String _kFollowed = 'sports.followed_matches.v1';

  /// Au-delà, un match passé n'a plus rien à dire : on l'oublie.
  static const Duration _keepAfterKickoff = Duration(days: 2);

  /// Plafond dur. Un client peut suivre beaucoup de matchs, mais pas un
  /// nombre illimité : la liste vit en mémoire et dans les préférences,
  /// et ce code doit tenir sur un téléphone de 256 Mo.
  static const int _maxFollowed = 200;

  final Map<String, SportEvent> _byId = <String, SportEvent>{};
  bool _loaded = false;

  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Émet à chaque ajout/retrait : les écrans s'y abonnent pour se
  /// rafraîchir sans re-interroger le réseau.
  Stream<void> get changes => _changes.stream;

  /// Les matchs suivis, du plus proche au plus lointain. Les rencontres
  /// sans date connue passent en dernier plutôt que d'être jetées.
  List<SportEvent> get all {
    final List<SportEvent> list = _byId.values.toList();
    list.sort((SportEvent a, SportEvent b) {
      final DateTime? da = a.startsAt;
      final DateTime? db = b.startsAt;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return List<SportEvent>.unmodifiable(list);
  }

  bool isFollowed(String matchId) => _byId.containsKey(matchId);

  int get count => _byId.length;

  /// À appeler une fois au démarrage de l'écran Sport. Idempotent, et
  /// silencieux en cas de préférences illisibles (on repart d'une liste
  /// vide plutôt que de planter l'écran).
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_kFollowed);
      if (raw == null || raw.isEmpty) return;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final Object? item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final SportEvent ev = SportEvent.fromJson(item);
        if (ev.id.isNotEmpty) _byId[ev.id] = ev;
      }
      if (_purgeStale()) await _save();
    } catch (e) {
      if (kDebugMode) debugPrint('[MatchsSuivis] lecture KO: $e');
    }
  }

  /// Suit ou ne suit plus ce match. Renvoie l'état APRÈS bascule, pour
  /// que l'appelant mette son bouton à jour sans relire la liste.
  Future<bool> toggle(SportEvent ev) async {
    await ensureLoaded();
    if (ev.id.isEmpty) return false;
    final bool nowFollowed = !_byId.containsKey(ev.id);
    if (nowFollowed) {
      if (_byId.length >= _maxFollowed) {
        // Plein : on libère la place la plus ancienne plutôt que de
        // refuser en silence — un refus muet passerait pour un bug.
        final List<SportEvent> sorted = all;
        if (sorted.isNotEmpty) _byId.remove(sorted.first.id);
      }
      _byId[ev.id] = ev;
    } else {
      _byId.remove(ev.id);
    }
    _purgeStale();
    await _save();
    if (!_changes.isClosed) _changes.add(null);
    return nowFollowed;
  }

  /// Oublie tout (bouton « vider » des réglages).
  Future<void> clear() async {
    await ensureLoaded();
    _byId.clear();
    await _save();
    if (!_changes.isClosed) _changes.add(null);
  }

  /// Rafraîchit le résumé mémorisé d'un match déjà suivi — typiquement
  /// quand le score arrive. N'ajoute JAMAIS un match non suivi : c'est
  /// ce qui garantit que la liste ne contient que des choix du client.
  Future<void> refreshKnown(Iterable<SportEvent> fresh) async {
    await ensureLoaded();
    bool changed = false;
    for (final SportEvent ev in fresh) {
      if (ev.id.isEmpty || !_byId.containsKey(ev.id)) continue;
      _byId[ev.id] = ev;
      changed = true;
    }
    if (changed) {
      await _save();
      if (!_changes.isClosed) _changes.add(null);
    }
  }

  /// Retire les matchs joués il y a plus de [_keepAfterKickoff].
  /// Renvoie `true` si quelque chose a été retiré.
  bool _purgeStale() {
    final DateTime now = DateTime.now();
    final List<String> stale = <String>[];
    for (final MapEntry<String, SportEvent> e in _byId.entries) {
      final DateTime? k = e.value.startsAt;
      // Date inconnue → on garde : mieux vaut une ligne en trop qu'un
      // match choisi qui disparaît sans explication.
      if (k == null) continue;
      if (now.difference(k) > _keepAfterKickoff) stale.add(e.key);
    }
    for (final String id in stale) {
      _byId.remove(id);
    }
    return stale.isNotEmpty;
  }

  Future<void> _save() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kFollowed,
        jsonEncode(all.map((SportEvent e) => e.toJson()).toList()),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[MatchsSuivis] écriture KO: $e');
    }
  }
}
