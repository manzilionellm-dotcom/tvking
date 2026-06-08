// =========================================================
//  channel_health_repository.dart — Santé des chaînes
// =========================================================
//  Objectif : pousser les chaînes MORTES au fond et garder les chaînes
//  FLUIDES (qui répondent) devant.
//
//  Deux sources de vérité, combinées :
//    1. SONDE réseau au démarrage — UNIQUEMENT sur un sous-ensemble (les
//       plus populaires / affichées en premier, ~80). On NE teste PAS les
//       12 000 chaînes : ça ferait bannir l'IP par le fournisseur.
//       Concurrence limitée, timeout court, résultat mis en cache (TTL).
//    2. USAGE réel — le lecteur signale succès/échec de lecture (branché
//       ailleurs) : une chaîne qui plante recule, une qui marche avance.
//
//  `sortByHealth()` réordonne une liste : vivantes/inconnues d'abord
//  (ordre préservé), mortes à la fin. ChangeNotifier → l'accueil se
//  re-trie tout seul quand les sondes finissent.
//
//  Aucune dépendance au cast.
// =========================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../channels/domain/channel.dart';
import 'popularity_repository.dart';

/// État de santé d'une chaîne.
class _Health {
  _Health({required this.probeOk, required this.ts});
  bool? probeOk; // null = jamais sondé
  int ts; // ms epoch du dernier verdict
}

class ChannelHealthRepository extends ChangeNotifier {
  ChannelHealthRepository._();
  static final ChannelHealthRepository instance = ChannelHealthRepository._();

  static const String _kKey = 'channel.health.v1';
  static const int _kProbeLimit = 80; // nb max de chaînes sondées au boot
  static const int _kConcurrency = 4; // sondes simultanées
  static const Duration _kTimeout = Duration(seconds: 4);
  static const int _kTtlMs = 6 * 3600 * 1000; // re-sonde après 6 h

  final Map<String, _Health> _map = <String, _Health>{};
  bool _initialized = false;
  bool _probing = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      final String? raw = p.getString(_kKey);
      if (raw != null) {
        final Object? d = jsonDecode(raw);
        if (d is Map) {
          d.forEach((Object? k, Object? v) {
            if (v is Map) {
              _map['$k'] = _Health(
                probeOk: v['ok'] is bool ? v['ok'] as bool : null,
                ts: (v['ts'] as num?)?.toInt() ?? 0,
              );
            }
          });
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Health] load: $e');
    }
  }

  /// `true` si la chaîne est CONNUE morte (sonde KO ou échec de lecture).
  bool isDead(String id) => _map[id]?.probeOk == false;

  /// Réordonne : vivantes/inconnues d'abord (ordre préservé), mortes après.
  List<Channel> sortByHealth(List<Channel> list) {
    if (_map.isEmpty) return list;
    final List<Channel> alive = <Channel>[];
    final List<Channel> dead = <Channel>[];
    for (final Channel c in list) {
      (isDead(c.id) ? dead : alive).add(c);
    }
    if (dead.isEmpty) return list;
    return <Channel>[...alive, ...dead];
  }

  /// Le lecteur appelle ceci quand une chaîne a JOUÉ correctement.
  void recordPlaySuccess(String id) => _record(id, true);

  /// Le lecteur appelle ceci quand une chaîne a ÉCHOUÉ (erreur / écran noir).
  void recordPlayFailure(String id) => _record(id, false);

  void _record(String id, bool ok) {
    if (id.isEmpty) return;
    _map[id] = _Health(probeOk: ok, ts: DateTime.now().millisecondsSinceEpoch);
    notifyListeners();
    unawaited(_persist());
  }

  /// Sonde en ARRIÈRE-PLAN les chaînes les plus susceptibles d'être vues
  /// (top popularité), bornées à [_kProbeLimit]. Ne bloque jamais l'UI.
  Future<void> probeTop(List<Channel> allChannels) async {
    if (_probing || allChannels.isEmpty) return;
    _probing = true;
    try {
      final List<Channel> ranked = PopularityRepository.instance
          .getPopularChannels(allChannels, top: _kProbeLimit);
      final int now = DateTime.now().millisecondsSinceEpoch;
      final List<Channel> todo = ranked.where((Channel c) {
        final _Health? h = _map[c.id];
        return h == null || now - h.ts > _kTtlMs;
      }).toList();
      if (todo.isEmpty) return;

      int next = 0;
      Future<void> worker() async {
        while (true) {
          final int i = next++;
          if (i >= todo.length) return;
          final Channel c = todo[i];
          final bool ok = await _probe(c.streamUrl);
          _map[c.id] =
              _Health(probeOk: ok, ts: DateTime.now().millisecondsSinceEpoch);
        }
      }

      await Future.wait(
        List<Future<void>>.generate(_kConcurrency, (_) => worker()),
      );
      await _persist();
      notifyListeners();
    } finally {
      _probing = false;
    }
  }

  /// Sonde "légère" : on ouvre le flux et on regarde juste s'il répond.
  /// On demande 2 octets (Range) et on coupe aussitôt → pas de download.
  /// User-Agent VLC : beaucoup de serveurs IPTV refusent les UA inconnus.
  Future<bool> _probe(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return false;
    final http.Client client = http.Client();
    try {
      final http.Request req = http.Request('GET', uri)
        ..headers['Range'] = 'bytes=0-1'
        ..headers['User-Agent'] = 'VLC/3.0.18 LibVLC/3.0.18';
      final http.StreamedResponse resp =
          await client.send(req).timeout(_kTimeout);
      return resp.statusCode >= 200 && resp.statusCode < 400;
    } catch (_) {
      return false; // timeout, 404, connexion refusée… = morte
    } finally {
      client.close(); // coupe le flux immédiatement
    }
  }

  Future<void> _persist() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      final Map<String, dynamic> out = <String, dynamic>{
        for (final MapEntry<String, _Health> e in _map.entries)
          e.key: <String, dynamic>{'ok': e.value.probeOk, 'ts': e.value.ts},
      };
      await p.setString(_kKey, jsonEncode(out));
    } catch (_) {/* best-effort */}
  }
}
