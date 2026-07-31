// =========================================================
//  startup_ad_repository.dart — Pub vidéo au démarrage
// =========================================================
//  Récupère la config de pub posée par le panel (`GET /api/ad`) et
//  décide si on doit la montrer (fréquence : à chaque ouverture, ou 1×
//  par jour via SharedPreferences). Best-effort : réseau KO = pas de pub.
//  Aucune dépendance au cast.
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../subscription/data/subscription_backend.dart';
import '../../subscription/data/subscription_state.dart';

/// Config d'une pub vidéo de démarrage.
@immutable
class AdConfig {
  const AdConfig({
    required this.enabled,
    required this.url,
    required this.skip,
    required this.freq,
  });

  final bool enabled;
  final String url;
  final int skip; // secondes avant que « Passer » apparaisse
  final String freq; // 'always' | 'daily'

  static const AdConfig none =
      AdConfig(enabled: false, url: '', skip: 5, freq: 'always');
}

class StartupAdRepository {
  StartupAdRepository._();
  static final StartupAdRepository instance = StartupAdRepository._();

  AdConfig _config = AdConfig.none;
  AdConfig get config => _config;

  /// Récupère la config distante. Retourne la config (mise en cache).
  Future<AdConfig> fetch() async {
    try {
      final http.Response resp = await http
          .get(Uri.parse('$kSubscriptionBaseUrl/api/ad'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return _config;
      final Object? d = jsonDecode(resp.body);
      if (d is! Map) return _config;
      final String url = (d['url'] ?? '').toString();
      final Object? rawSkip = d['skip'];
      final int skip = rawSkip is int
          ? rawSkip
          : (int.tryParse('${rawSkip ?? ''}') ?? 5);
      _config = AdConfig(
        enabled: d['enabled'] == true && url.isNotEmpty,
        url: url,
        skip: skip.clamp(0, 60),
        freq: (d['freq'] ?? 'always').toString(),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[StartupAd] $e');
    }
    return _config;
  }

  /// Faut-il montrer la pub maintenant ? (selon enabled + fréquence)
  Future<bool> shouldShow() async {
    final AdConfig c = _config;
    if (!c.enabled || c.url.isEmpty) return false;
    // « Acheter sans pubs » : un abonné PAYANT ne voit jamais la pub de
    // démarrage (même règle que les cartes d'affiliation de l'accueil).
    if (SubscriptionState.instance.status == SubscriptionStatus.paid) {
      return false;
    }
    if (c.freq != 'daily') return true; // 'always' = à chaque ouverture
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getString('ad_last_day') != _dayKey();
    } catch (_) {
      return true;
    }
  }

  /// Mémorise qu'on a montré la pub aujourd'hui (utile pour 'daily').
  Future<void> markShown() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('ad_last_day', _dayKey());
    } catch (_) {}
  }

  String _dayKey() {
    final DateTime n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }
}
