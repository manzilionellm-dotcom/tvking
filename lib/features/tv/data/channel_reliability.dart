// =========================================================
//  channel_reliability.dart — Fiabilité par chaîne (n°38)
// =========================================================
//  Compte, PAR CHAÎNE, les ouvertures réussies (première image dessinée)
//  et les échecs DÉFINITIFS (toute la cascade de lecture épuisée — même
//  signal que la Boîte noire). Le ratio donne un score de fiabilité
//  local, appris de l'usage réel du foyer : une chaîne qui échoue trois
//  fois sur quatre chez CE client mérite un petit badge discret sur sa
//  carte — avant qu'il ne perde encore 20 secondes dessus.
//
//  Honnêteté du score :
//    • pas de verdict avant 3 tentatives (un raté isolé n'est pas un état) ;
//    • vieillissement par division par deux au-delà de 24 échantillons →
//      une chaîne réparée côté panel se « rachète » vite ;
//    • plafond d'entrées (400, éviction des moins échantillonnées) →
//      les prefs restent bornées même sur une playlist de 10 000 chaînes.
//
//  Aucun réseau, aucun envoi : c'est une statistique 100 % locale.
// =========================================================
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChannelReliability extends ChangeNotifier {
  ChannelReliability._();
  static final ChannelReliability instance = ChannelReliability._();

  static const String _kKey = 'tv.reliability.v1';

  /// Seuil « douteuse » : moins de 40 % d'ouvertures réussies.
  static const double flakyThreshold = 0.4;

  /// Verdict interdit avant ce nombre de tentatives.
  static const int minSamples = 3;

  /// Au-delà, on divise les deux compteurs par deux (vieillissement).
  static const int _ageAfter = 24;

  /// Plafond d'entrées mémorisées.
  static const int _maxEntries = 400;

  // id → [réussites, échecs]
  final Map<String, List<int>> _counts = <String, List<int>>{};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_kKey);
      if (raw == null || raw.isEmpty) return;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      decoded.forEach((String id, Object? v) {
        if (v is List && v.length == 2 && v[0] is int && v[1] is int) {
          _counts[id] = <int>[v[0] as int, v[1] as int];
        }
      });
      notifyListeners();
    } catch (_) {
      // best-effort : donnée illisible → on repart de zéro.
    }
  }

  void recordSuccess(String channelId) => _record(channelId, ok: true);

  void recordFailure(String channelId) => _record(channelId, ok: false);

  void _record(String channelId, {required bool ok}) {
    if (channelId.isEmpty) return;
    // Ré-insertion en fin de Map → l'ordre d'itération reflète la
    // fraîcheur (les plus anciennes en tête pour l'éviction).
    final List<int> c = _counts.remove(channelId) ?? <int>[0, 0];
    if (ok) {
      c[0]++;
    } else {
      c[1]++;
    }
    // Vieillissement : le passé lointain pèse moitié moins que le récent.
    if (c[0] + c[1] > _ageAfter) {
      c[0] = (c[0] / 2).ceil();
      c[1] = (c[1] / 2).ceil();
    }
    _counts[channelId] = c;
    // Plafond : on évince d'abord les entrées les moins échantillonnées
    // parmi les plus anciennes (itération = ordre d'insertion).
    while (_counts.length > _maxEntries) {
      _counts.remove(_counts.keys.first);
    }
    notifyListeners();
    _persist();
  }

  /// Score 0..1 (part d'ouvertures réussies), ou null si < [minSamples].
  double? scoreOf(String channelId) {
    final List<int>? c = _counts[channelId];
    if (c == null) return null;
    final int total = c[0] + c[1];
    if (total < minSamples) return null;
    return c[0] / total;
  }

  /// Vrai si la chaîne échoue la plupart du temps CHEZ CE CLIENT
  /// (score connu et sous [flakyThreshold]).
  bool isFlaky(String channelId) {
    final double? s = scoreOf(channelId);
    return s != null && s < flakyThreshold;
  }

  Future<void> _persist() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKey, jsonEncode(_counts));
    } catch (_) {
      // best-effort
    }
  }
}
