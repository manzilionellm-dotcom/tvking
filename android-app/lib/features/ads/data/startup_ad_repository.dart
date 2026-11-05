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

  static const AdConfig none = AdConfig(
    enabled: false,
    url: '',
    skip: 5,
    freq: 'always',
  );
}

class StartupAdRepository {
  StartupAdRepository._();
  static final StartupAdRepository instance = StartupAdRepository._();

  /// Injections de tests : aucun serveur ou flux client n'est appelé.
  @visibleForTesting
  http.Client? client;
  @visibleForTesting
  String? baseUrl;
  @visibleForTesting
  DateTime Function()? clock;

  AdConfig _config = AdConfig.none;
  AdConfig get config => _config;

  /// Les écrans écoutent ce compteur. Il avance à chaque lecture
  /// réussie du panel (même si l'URL n'a pas changé : un second
  /// enregistrement doit réveiller la box). Le cache local, lui,
  /// ne l'avance pas.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static const String _kCache = 'zuno.ad.cache.v1';
  static const String _kLastUrl = 'ad_last_url';

  /// Dernière pub déjà lue, sans réseau. Faux si rien n'est en cache.
  /// L'ouverture n'attend plus le Worker pour décider.
  Future<bool> warmFromCache() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String raw = prefs.getString(_kCache) ?? '';
      if (raw.isEmpty) return false;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      _config = _parse(decoded);
      return _config.enabled;
    } catch (_) {
      return false;
    }
  }

  /// Récupère la config distante. Retourne la config (mise en cache).
  Future<AdConfig> fetch({bool strict = false}) async {
    final http.Client c = client ?? http.Client();
    final bool owned = client == null;
    try {
      final http.Response resp = await c
          .get(Uri.parse('${baseUrl ?? kSubscriptionBaseUrl}/api/ad'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) {
        throw StateError('Publicité : HTTP ${resp.statusCode}');
      }
      final Object? d = jsonDecode(resp.body);
      if (d is! Map || d['enabled'] is! bool) {
        throw const FormatException('Configuration de publicité invalide');
      }
      _config = _parse(d);
      revision.value = revision.value + 1;
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _kCache,
          jsonEncode(<String, Object>{
            'enabled': _config.enabled,
            'url': _config.url,
            'skip': _config.skip,
            'freq': _config.freq,
          }),
        );
      } catch (_) {
        // Le cache sert à la prochaine ouverture. La pub de cette
        // lecture est déjà dans [config].
      }
    } catch (e) {
      if (strict) rethrow;
      if (kDebugMode) debugPrint('[StartupAd] $e');
      _config = AdConfig.none;
    } finally {
      if (owned) c.close();
    }
    return _config;
  }

  AdConfig _parse(Map<dynamic, dynamic> d) {
    final String url = (d['url'] ?? '').toString().trim();
    final Uri? uri = Uri.tryParse(url);
    final bool validUrl =
        uri != null &&
        uri.hasAuthority &&
        <String>['http', 'https'].contains(uri.scheme);
    if (d['enabled'] == true && !validUrl) {
      throw const FormatException('URL de publicité invalide');
    }
    final Object? rawSkip = d['skip'];
    final int skip = rawSkip is int
        ? rawSkip
        : (int.tryParse('${rawSkip ?? ''}') ?? 5);
    return AdConfig(
      enabled: d['enabled'] == true && validUrl,
      url: url,
      skip: skip.clamp(0, 60),
      freq: d['freq'] == 'daily' ? 'daily' : 'always',
    );
  }

  /// Faut-il montrer la pub maintenant ? (selon enabled + fréquence)
  /// Une pub quotidienne déjà vue aujourd'hui reste cachée, sauf si
  /// le panel a changé l'adresse : c'est une autre publicité.
  Future<bool> shouldShow() async {
    final AdConfig c = _config;
    if (!c.enabled || c.url.isEmpty) return false;
    if (c.freq != 'daily') return true; // 'always' = à chaque ouverture
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (prefs.getString('ad_last_day') != _dayKey()) return true;
      return prefs.getString(_kLastUrl) != c.url;
    } catch (_) {
      return true;
    }
  }

  /// Mémorise qu'on a montré la pub aujourd'hui (utile pour 'daily').
  Future<void> markShown() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('ad_last_day', _dayKey());
      await prefs.setString(_kLastUrl, _config.url);
    } catch (_) {}
  }

  @visibleForTesting
  void resetForTesting() {
    _config = AdConfig.none;
    client = null;
    baseUrl = null;
    clock = null;
    if (revision.value != 0) revision.value = 0;
  }

  String _dayKey() {
    final DateTime n = clock?.call() ?? DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }
}
