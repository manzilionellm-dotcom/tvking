// =========================================================
//  live_alert_plan.dart — But, coup d'envoi, fin de match
// =========================================================
//  Décisions pures à partir de deux photos du direct. Pas de
//  réseau, pas de notification. Le premier passage apprend les
//  scores et se tait : sinon l'ouverture de l'app crierait pour
//  tous les matchs déjà commencés.
//
//  Une fin n'est annoncée qu'après DEUX photos sans le match.
//  Une seule absence peut être un trou du serveur, pas un coup
//  de sifflet.
// =========================================================

import 'sport_models.dart';

enum LiveAlertKind { goal, started, ended }

class LiveAlert {
  const LiveAlert(this.kind, this.event);

  final LiveAlertKind kind;
  final SportEvent event;
}

class LiveAlertPlan {
  final Map<String, int> _totals = <String, int>{};
  final Map<String, SportEvent> _seen = <String, SportEvent>{};
  final Map<String, int> _misses = <String, int>{};
  final Set<String> _ended = <String>{};
  bool _baseline = false;

  /// Tests : repart de zéro, comme au premier lancement.
  void reset() {
    _totals.clear();
    _seen.clear();
    _misses.clear();
    _ended.clear();
    _baseline = false;
  }

  static int? total(SportEvent e) {
    final int? h = int.tryParse(e.homeScore ?? '');
    final int? a = int.tryParse(e.awayScore ?? '');
    if (h == null || a == null) return null;
    return h + a;
  }

  /// [fresh] = la photo complète du direct, pas seulement les favoris.
  List<LiveAlert> consume(List<SportEvent> fresh) {
    final Map<String, SportEvent> byId = <String, SportEvent>{
      for (final SportEvent e in fresh)
        if (e.id.isNotEmpty) e.id: e,
    };
    final List<LiveAlert> out = <LiveAlert>[];

    if (!_baseline) {
      // Une photo vide n'apprend rien : on attend la première vraie
      // liste. Sinon le trou d'un appel raté ferait croire que TOUS
      // les matchs suivants viennent de commencer.
      if (byId.isEmpty) return const <LiveAlert>[];
      for (final SportEvent e in byId.values) {
        final int? t = total(e);
        if (t != null) _totals[e.id] = t;
        _seen[e.id] = e;
      }
      _baseline = true;
      return const <LiveAlert>[];
    }

    for (final SportEvent e in byId.values) {
      final SportEvent? before = _seen[e.id];
      final int? t = total(e);
      final int? avant = _totals[e.id];
      if (t != null && avant != null && t > avant) {
        out.add(LiveAlert(LiveAlertKind.goal, e));
      }
      if (t != null) _totals[e.id] = t;
      final bool wasLive = before != null && before.isLive;
      if (e.isLive && !wasLive && !_ended.contains(e.id)) {
        out.add(LiveAlert(LiveAlertKind.started, e));
      }
      _seen[e.id] = e;
      _misses.remove(e.id);
    }

    final List<String> tracked = _seen.keys.toList(growable: false);
    for (final String id in tracked) {
      if (byId.containsKey(id)) continue;
      final SportEvent? last = _seen[id];
      if (last == null || !last.isLive || _ended.contains(id)) continue;
      final int n = (_misses[id] ?? 0) + 1;
      _misses[id] = n;
      if (n >= 2) {
        _ended.add(id);
        _misses.remove(id);
        out.add(LiveAlert(LiveAlertKind.ended, last));
      }
    }
    return out;
  }
}
