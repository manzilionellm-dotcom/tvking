// =========================================================
//  predictions_service.dart — Les pronostics des fans, côté app
// =========================================================
//  Demande du propriétaire (06/09/2026) : « sondages et prédictions en
//  direct ». Avant un match, le client dit qui va gagner (1 / N / 2) et
//  voit aussitôt ce que pensent les autres fans, en pourcentage. Après
//  le coup d'envoi, le vote se ferme et le résultat tranche.
//
//  CE QUE C'EST : un sondage entre spectateurs. Pas d'argent, pas de
//  gain, pas de classement entre personnes — c'est ce qui le garde du
//  bon côté des règles des magasins, et c'est voulu.
//
//  CE QUE CE SERVICE GARANTIT :
//   1. MON VOTE SE VOIT TOUT DE SUITE, même hors ligne : il est mémorisé
//      localement avant d'être envoyé. Un vote qui « n'apparaît pas »
//      passe pour un bug ; on ne fait pas attendre le réseau.
//   2. LES POURCENTAGES SONT CEUX DU SERVEUR. On ne les recalcule pas
//      ici avec des chiffres partiels : la source de vérité est unique.
//   3. FERMÉ AU COUP D'ENVOI, décidé par l'app ET par le serveur. L'app
//      grise les boutons ; le serveur refuse quand même (409) si un client
//      tente le coup — deux verrous, une seule règle.
//   4. BEST-EFFORT ABSOLU : réseau coupé, serveur muet → on garde ce
//      qu'on avait, rien ne remonte à l'écran en erreur.
// =========================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../device/data/device_identity.dart';
import '../../subscription/data/subscription_backend.dart'
    show kSubscriptionBaseUrl;
import '../domain/sport_models.dart';

/// Les trois issues d'un duel. L'ordre est celui de l'affichage
/// (« 1 · N · 2 ») et celui du serveur.
enum Pick { home, draw, away }

Pick? pickFromWire(String? s) {
  switch (s) {
    case 'home':
      return Pick.home;
    case 'draw':
      return Pick.draw;
    case 'away':
      return Pick.away;
  }
  return null;
}

String pickToWire(Pick p) => p.name;

/// Ce que pensent les fans d'un match : comptes et pourcentages tels que
/// le serveur les a calculés. Immuable.
@immutable
class PredictionTally {
  const PredictionTally({
    this.total = 0,
    this.homePct = 0,
    this.drawPct = 0,
    this.awayPct = 0,
    this.mine,
  });

  final int total;
  final int homePct;
  final int drawPct;
  final int awayPct;

  /// Mon vote, s'il existe (mémorisé localement ou rendu par le serveur).
  final Pick? mine;

  int pct(Pick p) {
    switch (p) {
      case Pick.home:
        return homePct;
      case Pick.draw:
        return drawPct;
      case Pick.away:
        return awayPct;
    }
  }

  PredictionTally withMine(Pick? p) => PredictionTally(
        total: total,
        homePct: homePct,
        drawPct: drawPct,
        awayPct: awayPct,
        mine: p,
      );

  /// Lecture TOLÉRANTE du JSON serveur : un champ absent vaut 0, jamais une
  /// exception qui viderait la ligne du match.
  factory PredictionTally.fromJson(Map<String, dynamic> j, {Pick? localMine}) {
    final Object? pct = j['percent'];
    int read(String k) {
      if (pct is Map<String, dynamic>) {
        return int.tryParse('${pct[k] ?? 0}') ?? 0;
      }
      return 0;
    }

    return PredictionTally(
      total: int.tryParse('${j['total'] ?? 0}') ?? 0,
      homePct: read('home'),
      drawPct: read('draw'),
      awayPct: read('away'),
      // Le serveur fait foi s'il connaît mon vote ; sinon la mémoire locale.
      mine: pickFromWire(j['mine']?.toString()) ?? localMine,
    );
  }
}

class PredictionsService {
  PredictionsService._();
  static final PredictionsService instance = PredictionsService._();

  /// Mes votes, par identifiant de match : `{"2052478":"home",…}`.
  static const String _kMine = 'sports.predictions.mine.v1';

  /// Au-delà de cette taille, on oublie les plus anciens (les matchs
  /// passés n'ont plus rien à dire ; une saison ≈ 400 matchs).
  static const int _maxRemembered = 400;

  static const Duration _timeout = Duration(seconds: 7);

  final Map<String, Pick> _mine = <String, Pick>{};
  final Map<String, PredictionTally> _tallies = <String, PredictionTally>{};
  final Set<String> _loading = <String>{};
  bool _loaded = false;

  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Émet à chaque vote ou à chaque réponse serveur : les tuiles s'y
  /// abonnent pour se redessiner sans re-interroger le réseau.
  Stream<void> get changes => _changes.stream;

  /// Branchements remplaçables dans les tests (aucun réseau, aucun MAC).
  @visibleForTesting
  Future<Map<String, dynamic>?> Function(String matchId)? debugFetch;
  @visibleForTesting
  Future<Map<String, dynamic>?> Function(
      String matchId, Pick pick, DateTime? kickoff)? debugSend;

  /// Un vote est-il encore possible pour ce match ? Uniquement un DUEL,
  /// avec un coup d'envoi connu et pas encore passé, et pas en cours ni
  /// terminé selon la source. Fonction pure, testée.
  static bool isOpen(SportEvent e, DateTime now) {
    if (!e.isDuel || e.id.isEmpty) return false;
    final DateTime? k = e.startsAt;
    if (k == null) return false;
    if (!now.isBefore(k)) return false;
    // Un match déjà « en direct » ou fini n'accepte plus de pronostic,
    // même si l'horaire annoncé est dans le futur (report mal renseigné).
    if (e.isLive || e.hasScore) return false;
    return true;
  }

  /// Mon vote pour ce match, mémorisé localement ou rendu par le serveur.
  Pick? myPick(String matchId) => _mine[matchId];

  /// Ce que pensent les fans — `null` tant que le serveur n'a pas répondu.
  PredictionTally? tallyFor(String matchId) {
    final PredictionTally? t = _tallies[matchId];
    if (t == null) return null;
    return t.mine == null ? t.withMine(_mine[matchId]) : t;
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_kMine);
      if (raw == null || raw.isEmpty) return;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      decoded.forEach((String id, Object? v) {
        final Pick? p = pickFromWire(v?.toString());
        if (p != null && id.isNotEmpty) _mine[id] = p;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[Pronos] lecture KO: $e');
    }
  }

  /// Va chercher les pourcentages d'un match (une requête en vol au plus
  /// par match). Silencieux en cas d'échec : la tuile garde « — ».
  Future<void> load(String matchId) async {
    if (matchId.isEmpty || _loading.contains(matchId)) return;
    _loading.add(matchId);
    try {
      await ensureLoaded();
      final Map<String, dynamic>? j = await _fetch(matchId);
      if (j == null) return;
      _tallies[matchId] =
          PredictionTally.fromJson(j, localMine: _mine[matchId]);
      final Pick? serverMine = pickFromWire(j['mine']?.toString());
      if (serverMine != null && _mine[matchId] != serverMine) {
        _mine[matchId] = serverMine;
        await _save();
      }
      if (!_changes.isClosed) _changes.add(null);
    } catch (e) {
      if (kDebugMode) debugPrint('[Pronos] chargement KO: $e');
    } finally {
      _loading.remove(matchId);
    }
  }

  /// Vote (ou change de vote). Le choix est mémorisé AVANT l'envoi : il
  /// s'affiche tout de suite, réseau ou pas. Renvoie `false` si le
  /// serveur a refusé (coup d'envoi passé) ou n'a pas répondu — le vote
  /// local reste, il sera visible au client comme SON avis.
  Future<bool> vote(SportEvent e, Pick pick) async {
    if (e.id.isEmpty) return false;
    await ensureLoaded();
    _mine[e.id] = pick;
    _tallies[e.id] = (_tallies[e.id] ?? const PredictionTally()).withMine(pick);
    await _save();
    if (!_changes.isClosed) _changes.add(null);
    try {
      final Map<String, dynamic>? j = await _send(e.id, pick, e.startsAt);
      if (j == null) return false;
      _tallies[e.id] = PredictionTally.fromJson(j, localMine: pick);
      if (!_changes.isClosed) _changes.add(null);
      return true;
    } catch (err) {
      if (kDebugMode) debugPrint('[Pronos] vote KO: $err');
      return false;
    }
  }

  Future<Map<String, dynamic>?> _fetch(String matchId) async {
    final Future<Map<String, dynamic>?> Function(String)? o = debugFetch;
    if (o != null) return o(matchId);
    final String mac = await DeviceIdentity.instance.mac;
    final http.Response r = await http
        .get(
          Uri.parse('$kSubscriptionBaseUrl/api/sports/predict/'
              '${Uri.encodeComponent(matchId)}?mac=${Uri.encodeQueryComponent(mac)}'),
          headers: const <String, String>{'Accept': 'application/json'},
        )
        .timeout(_timeout);
    if (r.statusCode != 200) return null;
    final Object? decoded = jsonDecode(utf8.decode(r.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  Future<Map<String, dynamic>?> _send(
      String matchId, Pick pick, DateTime? kickoff) async {
    final Future<Map<String, dynamic>?> Function(String, Pick, DateTime?)? o =
        debugSend;
    if (o != null) return o(matchId, pick, kickoff);
    final String mac = await DeviceIdentity.instance.mac;
    final http.Response r = await http
        .post(
          Uri.parse('$kSubscriptionBaseUrl/api/sports/predict'),
          headers: const <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(<String, Object?>{
            'mac': mac,
            'match': matchId,
            'pick': pickToWire(pick),
            if (kickoff != null) 'kickoff': kickoff.toUtc().toIso8601String(),
          }),
        )
        .timeout(_timeout);
    if (r.statusCode != 200) return null;
    final Object? decoded = jsonDecode(utf8.decode(r.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  Future<void> _save() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      // Borne : on garde les derniers votes (l'ordre d'insertion d'une Map
      // Dart est stable, les plus anciens sont en tête).
      while (_mine.length > _maxRemembered) {
        _mine.remove(_mine.keys.first);
      }
      await prefs.setString(
        _kMine,
        jsonEncode(_mine.map(
            (String k, Pick v) => MapEntry<String, String>(k, pickToWire(v)))),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Pronos] écriture KO: $e');
    }
  }

  /// Simule un redémarrage : la mémoire est vidée, les préférences restent.
  @visibleForTesting
  Future<void> debugResetMemoryOnly() async {
    _mine.clear();
    _tallies.clear();
    _loading.clear();
    _loaded = false;
  }

  @visibleForTesting
  Future<void> debugReset() async {
    _mine.clear();
    _tallies.clear();
    _loading.clear();
    _loaded = false;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kMine);
    } catch (_) {
      // best-effort
    }
  }
}
