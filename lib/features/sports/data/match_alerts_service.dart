// =========================================================
//  match_alerts_service.dart — Alertes des GRANDS MATCHS
// =========================================================
//  Demande propriétaire (22/08) : « je veux les notifications des grands
//  matchs automatiquement — si le Real joue Chelsea — et les résultats
//  instantanés. Une app d'IPTV ET de notifications de match. »
//
//  DEUX ALERTES, jamais plus :
//    1. AVANT  : ~15 min avant le coup d'envoi (« coup d'envoi dans 15 min »)
//       → le client a le temps d'ouvrir la chaîne. Notification PROGRAMMÉE :
//         elle part même si l'app est fermée.
//    2. APRÈS  : le score final, une seule fois par match.
//
//  QUELS MATCHS ?
//    • les GRANDES AFFICHES servies par le worker (/api/sports/big : les
//      deux camps sont des clubs majeurs — Real–Chelsea oui, Real–petit
//      club non), travail mutualisé côté serveur, cache 30 min ;
//    • PLUS les matchs des équipes que le client a mises en favori
//      (SportsRepository) — là, tous ses matchs comptent ;
//    • PLUS les matchs qu'il a choisis UN PAR UN dans le coin Sport
//      (FollowedMatchesService). C'est le cas le plus fort : il a
//      explicitement demandé CE match-là, quel que soit le sport et
//      quelle que soit la ligue.
//
//  ANTI-SPAM (règle d'or) : chaque match ne déclenche qu'UNE alerte avant
//  et UNE alerte de résultat, mémorisées par identifiant de match. Un
//  redémarrage de l'app ne re-notifie donc jamais un match déjà annoncé.
//
//  BEST-EFFORT ABSOLU : réseau coupé, API muette, permission refusée…
//  rien ne remonte à l'appelant, rien ne bloque l'app.
// =========================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/i18n/l10n_now.dart';
import '../../../core/notifications/notification_service.dart';
import '../../subscription/data/subscription_backend.dart'
    show kSubscriptionBaseUrl;
import '../domain/sport_models.dart';
import 'followed_matches_service.dart';
import 'sports_repository.dart';

class MatchAlertsService {
  MatchAlertsService._();
  static final MatchAlertsService instance = MatchAlertsService._();

  /// Interrupteur Réglages (activé par défaut : c'est l'argument de vente).
  static const String prefMatches = 'notif.matches.enabled';

  /// Matchs déjà annoncés AVANT le coup d'envoi (ids TheSportsDB).
  static const String _kNotifiedSoon = 'notif.matches.soon.v1';

  /// Matchs dont le RÉSULTAT a déjà été annoncé.
  static const String _kNotifiedResult = 'notif.matches.result.v1';

  /// Plages d'identifiants de notification (séparées des autres familles :
  /// rappels EPG, annonces, ré-engagement — voir NotificationService).
  static const int _idBaseSoon = 930000;
  static const int _idBaseResult = 940000;

  /// Fenêtre d'anticipation : on programme les affiches des 48 prochaines
  /// heures. Au-delà, l'alarme serait annulée par l'OS avant d'être utile —
  /// et une nouvelle passe la reprogrammera de toute façon.
  static const Duration _horizon = Duration(hours: 48);

  /// Délai avant coup d'envoi.
  static const Duration _lead = Duration(minutes: 15);

  /// Fenêtre de FRAÎCHEUR d'un résultat : au-delà, le score n'est plus une
  /// nouvelle (le client l'a vu ailleurs), on se tait. Sans cette borne, le
  /// premier lancement de l'app annoncerait toute la saison d'un coup.
  static const Duration _resultWindow = Duration(hours: 6);

  /// Anti-martèlement : au maximum une passe toutes les 30 min.
  static const Duration _minGap = Duration(minutes: 30);
  DateTime? _lastRun;

  bool _running = false;

  /// Passe complète : récupère les affiches, programme les alertes d'avant
  /// match, annonce les résultats fraîchement connus. À appeler à l'arrivée
  /// sur l'accueil — l'anti-martèlement fait le reste.
  Future<void> refresh({bool force = false}) async {
    if (_running) return;
    final DateTime now = DateTime.now();
    if (!force && _lastRun != null && now.difference(_lastRun!) < _minGap) {
      return;
    }
    _running = true;
    try {
      if (!await NotificationService.instance.isEnabled(prefMatches)) return;
      final List<SportEvent> events = await _collect();
      if (events.isEmpty) return;
      await _scheduleKickoffs(events, now);
      await _announceResults(events, now);
      _lastRun = now;
    } catch (e) {
      if (kDebugMode) debugPrint('[Matchs] passe KO: $e');
    } finally {
      _running = false;
    }
  }

  // ---------------------------------------------------------------
  //  Collecte : grandes affiches (worker) + équipes favorites (local)
  // ---------------------------------------------------------------

  Future<List<SportEvent>> _collect() async {
    final Map<String, SportEvent> byId = <String, SportEvent>{};
    // 1) Grandes affiches — UNE requête, tout le travail est côté serveur.
    try {
      final http.Response r = await http
          .get(Uri.parse('$kSubscriptionBaseUrl/api/sports/big'))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final Object? decoded = jsonDecode(utf8.decode(r.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          final Object? list = decoded['matches'];
          if (list is List) {
            for (final Object? raw in list) {
              if (raw is! Map<String, dynamic>) continue;
              final SportEvent ev = SportEvent.fromJson(raw);
              if (ev.id.isNotEmpty) byId[ev.id] = ev;
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Matchs] grandes affiches KO: $e');
    }
    // 2) Équipes FAVORITES du client : tous leurs matchs comptent, même
    //    face à un adversaire modeste (c'est SON équipe).
    try {
      for (final SportTeam t in SportsRepository.instance.favorites) {
        final SportsEvents e = SportsRepository.instance.eventsFor(t.id);
        for (final SportEvent ev in <SportEvent>[...e.next, ...e.last]) {
          if (ev.id.isNotEmpty) byId[ev.id] = ev;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Matchs] favoris KO: $e');
    }
    // 3) Matchs choisis UN PAR UN. Ils sont ajoutés EN DERNIER et
    //    volontairement : ce sont des choix explicites, ils doivent
    //    survivre même si le serveur ne les classe plus parmi les
    //    grandes affiches (une finale passe, un favori change de camp…).
    try {
      await FollowedMatchesService.instance.ensureLoaded();
      for (final SportEvent ev in FollowedMatchesService.instance.all) {
        // On ne veut pas ÉCRASER une version fraîche du serveur (elle
        // porte le score) par le résumé mémorisé, plus ancien.
        if (ev.id.isNotEmpty) byId.putIfAbsent(ev.id, () => ev);
      }
      // Au passage, on rafraîchit les résumés mémorisés avec ce que le
      // serveur vient de dire : le score s'affiche alors hors ligne.
      await FollowedMatchesService.instance.refreshKnown(byId.values);
    } catch (e) {
      if (kDebugMode) debugPrint('[Matchs] matchs suivis KO: $e');
    }
    return byId.values.toList(growable: false);
  }

  // ---------------------------------------------------------------
  //  1. Alerte AVANT le coup d'envoi (programmée, l'app peut être fermée)
  // ---------------------------------------------------------------

  Future<void> _scheduleKickoffs(
      List<SportEvent> events, DateTime now) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Set<String> done =
        (prefs.getStringList(_kNotifiedSoon) ?? const <String>[]).toSet();
    bool changed = false;
    for (final SportEvent ev in events) {
      if (done.contains(ev.id)) continue;
      // `startsAt` (modèle) fait la conversion UTC → locale : le panel donne
      // l'heure du match en UTC, l'alarme doit partir à l'heure du CLIENT.
      final DateTime? kickoff = ev.startsAt;
      if (kickoff == null) continue;
      final DateTime when = kickoff.subtract(_lead);
      // Trop tard (match commencé ou dans moins de 15 min) ou trop loin.
      if (when.isBefore(now)) continue;
      if (kickoff.difference(now) > _horizon) continue;
      await NotificationService.instance.scheduleAt(
        id: _idBaseSoon + _slot(ev.id),
        when: when,
        title: l10nNow.notifMatchSoonTitle,
        body: l10nNow.notifMatchKickoffIn(
          _label(ev),
          _lead.inMinutes,
        ),
      );
      done.add(ev.id);
      changed = true;
    }
    if (changed) {
      await prefs.setStringList(_kNotifiedSoon, _trim(done));
    }
  }

  // ---------------------------------------------------------------
  //  2. RÉSULTAT — une seule fois par match, dès que le score est connu
  // ---------------------------------------------------------------

  Future<void> _announceResults(
      List<SportEvent> events, DateTime now) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Set<String> done =
        (prefs.getStringList(_kNotifiedResult) ?? const <String>[]).toSet();
    bool changed = false;
    for (final SportEvent ev in events) {
      if (done.contains(ev.id)) continue;
      if (!ev.hasScore) continue;
      final DateTime? kickoff = ev.startsAt;
      // On n'annonce que les matchs RÉCENTS : au boot, l'API renvoie aussi
      // des rencontres vieilles de plusieurs semaines — les annoncer serait
      // absurde (et bruyant).
      if (kickoff == null) continue;
      if (now.difference(kickoff) > _resultWindow) continue;
      if (kickoff.isAfter(now)) continue;
      await NotificationService.instance.showNow(
        id: _idBaseResult + _slot(ev.id),
        title: l10nNow.notifMatchResultTitle,
        // Corps VOLONTAIREMENT non traduit : « Real Madrid 2 – 1 Chelsea »
        // se lit dans toutes les langues.
        body: '${ev.home} ${ev.homeScore} – ${ev.awayScore} ${ev.away}',
      );
      done.add(ev.id);
      changed = true;
    }
    if (changed) {
      await prefs.setStringList(_kNotifiedResult, _trim(done));
    }
  }

  // ---------------------------------------------------------------
  //  Outils
  // ---------------------------------------------------------------

  /// « Real Madrid – Chelsea » (ou le nom brut si les camps manquent).
  @visibleForTesting
  String label(SportEvent ev) => _label(ev);

  String _label(SportEvent ev) {
    if (ev.home.isNotEmpty && ev.away.isNotEmpty) {
      return '${ev.home} – ${ev.away}';
    }
    return ev.name;
  }

  /// Identifiant de notification STABLE dérivé de l'id du match : deux
  /// passes successives visent la même notification (donc remplacement,
  /// jamais de doublon). Borné à 1000 emplacements par famille.
  @visibleForTesting
  int slot(String matchId) => _slot(matchId);

  int _slot(String matchId) {
    int h = 0;
    for (final int c in matchId.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h % 1000;
  }

  /// Borne la mémoire anti-spam (une saison de football, c'est ~400 matchs
  /// par famille) : on garde les 400 derniers ids.
  List<String> _trim(Set<String> ids) {
    final List<String> list = ids.toList();
    if (list.length <= 400) return list;
    return list.sublist(list.length - 400);
  }
}
