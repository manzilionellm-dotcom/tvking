// =========================================================
//  promo_banner_repository.dart — Les bannières du panel, sur la box
// =========================================================
//  Lit `GET /api/banners` (contrat dans panel_board.dart). Tant que le
//  Worker ne sert pas cette route (404 aujourd'hui), la liste est vide
//  et l'accueil ne change pas. Cache local : l'accueil montre tout de
//  suite la dernière liste connue, puis le réseau la rafraîchit.
//
//  Le canal « signal » appelle [refresh] quand le panel publie
//  (ordre `banner`) : la bannière arrive sur la box sans attendre.
//
//  Compteurs : combien de fois chaque bannière a été montrée AUJOURD'HUI
//  (remis à zéro quand la date change) et jusqu'à quand une bannière
//  fermée reste cachée (7 jours). SharedPreferences, en JSON. Rien
//  n'est envoyé au serveur.
// =========================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../subscription/data/subscription_backend.dart';
import '../domain/panel_board.dart';

class PromoBannerRepository extends ChangeNotifier {
  PromoBannerRepository._();
  static final PromoBannerRepository instance = PromoBannerRepository._();

  static const String _kCache = 'zuno.promo.cache.v1';
  static const String _kCounters = 'zuno.promo.counters.v1';
  static const Duration _timeout = Duration(seconds: 6);

  /// Client injectable (tests). `null` = un client http par appel.
  @visibleForTesting
  http.Client? client;

  /// Adresse de base injectable (tests). `null` = le Worker configuré.
  @visibleForTesting
  String? baseUrl;

  List<PromoBanner> _banners = const <PromoBanner>[];
  Map<String, int> _shownToday = <String, int>{};
  Map<String, int> _dismissedUntilMs = <String, int>{};
  String _day = '';
  bool _initialized = false;

  List<PromoBanner> get banners => _banners;

  /// Affichages du jour, par id.
  Map<String, int> shownToday(DateTime now) {
    _rollDay(now);
    return Map<String, int>.unmodifiable(_shownToday);
  }

  /// Ids fermés encore valables à [nowMs].
  Set<String> dismissedAt(int nowMs) => <String>{
        for (final MapEntry<String, int> e in _dismissedUntilMs.entries)
          if (e.value > nowMs) e.key,
      };

  /// Cache puis réseau. Appelable plusieurs fois : la deuxième ne fait rien.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _loadLocal();
    unawaited(refresh());
  }

  /// Relit la liste. 200 → remplace (et met en cache). 404 → liste vide
  /// (le panel n'a rien publié ou la route n'existe pas encore). Autre
  /// code ou réseau coupé → on garde ce qu'on a.
  Future<void> refresh() async {
    final http.Client c = client ?? http.Client();
    try {
      final String base = baseUrl ?? kSubscriptionBaseUrl;
      final http.Response resp =
          await c.get(Uri.parse('$base/api/banners')).timeout(_timeout);
      if (resp.statusCode == 404) {
        await _replace(const <PromoBanner>[], rawJson: '[]');
        return;
      }
      if (resp.statusCode != 200) return;
      final Object? decoded = jsonDecode(resp.body);
      await _replace(parsePromoBanners(decoded), rawJson: resp.body);
    } catch (e) {
      if (kDebugMode) debugPrint('[Bannières] $e');
    } finally {
      if (client == null) c.close();
    }
  }

  /// La bannière vient d'apparaître : +1 pour aujourd'hui.
  Future<void> noteShown(String id, {DateTime? now}) async {
    _rollDay(now ?? DateTime.now());
    _shownToday[id] = (_shownToday[id] ?? 0) + 1;
    await _saveCounters();
  }

  /// « Fermer » : plus cette bannière pendant [kPromoDismissFor].
  Future<void> dismiss(String id, {DateTime? now}) async {
    final DateTime at = now ?? DateTime.now();
    _rollDay(at);
    _dismissedUntilMs[id] = at.add(kPromoDismissFor).millisecondsSinceEpoch;
    await _saveCounters();
    notifyListeners();
  }

  /// Compteurs du jour courant (un changement de date les remet à zéro)
  /// et oubli des fermetures échues.
  void _rollDay(DateTime now) {
    final String key = promoDayKey(now);
    if (key != _day) {
      _day = key;
      _shownToday = <String, int>{};
    }
    final int nowMs = now.millisecondsSinceEpoch;
    _dismissedUntilMs.removeWhere((String _, int until) => until <= nowMs);
  }

  Future<void> _replace(List<PromoBanner> next, {required String rawJson}) async {
    final bool changed = !_sameIds(next, _banners);
    _banners = next;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCache, rawJson);
    } catch (_) {}
    if (changed) notifyListeners();
  }

  static bool _sameIds(List<PromoBanner> a, List<PromoBanner> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].image != b[i].image) return false;
    }
    return true;
  }

  Future<void> _loadLocal() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_kCache);
      if (raw != null && raw.isNotEmpty) {
        _banners = parsePromoBanners(jsonDecode(raw));
      }
      final String? counters = prefs.getString(_kCounters);
      if (counters != null && counters.isNotEmpty) {
        final Object? d = jsonDecode(counters);
        if (d is Map) {
          _day = (d['day'] ?? '').toString();
          _shownToday = _intMap(d['shown']);
          _dismissedUntilMs = _intMap(d['dismissed_until']);
        }
      }
      _rollDay(DateTime.now());
    } catch (e) {
      if (kDebugMode) debugPrint('[Bannières] cache : $e');
      _banners = const <PromoBanner>[];
    }
  }

  static Map<String, int> _intMap(Object? raw) {
    if (raw is! Map) return <String, int>{};
    return <String, int>{
      for (final MapEntry<Object?, Object?> e in raw.entries)
        if (e.value is num) '${e.key}': (e.value! as num).toInt(),
    };
  }

  Future<void> _saveCounters() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kCounters,
        jsonEncode(<String, Object?>{
          'day': _day,
          'shown': _shownToday,
          'dismissed_until': _dismissedUntilMs,
        }),
      );
    } catch (_) {}
  }

  /// Remise à zéro (tests).
  @visibleForTesting
  void resetForTesting() {
    _banners = const <PromoBanner>[];
    _shownToday = <String, int>{};
    _dismissedUntilMs = <String, int>{};
    _day = '';
    _initialized = false;
    client = null;
    baseUrl = null;
  }
}
