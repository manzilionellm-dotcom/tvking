// =========================================================
//  watch_stats_service.dart — Statistiques personnelles de visionnage
// =========================================================
//  MODULE INDÉPENDANT (fonctionnalité n°15) : mesure le temps passé
//  devant l'app et les chaînes les plus regardées, PAR PROFIL, pour
//  l'écran « Mes statistiques » (Réglages).
//
//  MÉCANIQUE (zéro contact lecteur) : le lecteur alimente DÉJÀ
//  NowPlaying (le nom de la chaîne en cours, utilisé par le heartbeat
//  du panel). Ici on se contente d'ÉCHANTILLONNER cette valeur une fois
//  par minute : chaîne non vide → +1 minute au jour courant et à la
//  chaîne. Aucune requête réseau, aucune écoute du player.
//
//  STOCKAGE : SharedPreferences, clé SUFFIXÉE PAR PROFIL (comme les
//  autres dépôts par profil), JSON compact :
//    { "2026-07-04": {"t": 132, "c": {"TF1": 40, "beIN 1": 92}}, ... }
//  Taillé pour rester minuscule : 30 jours max (purge auto), 40 chaînes
//  max par jour. Écriture bufferisée (1 write/minute quand on regarde).
//
//  VIE PRIVÉE : tout est LOCAL à la box. Rien n'est envoyé au serveur.
// =========================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/profiles/profiles_repository.dart';
import '../../subscription/data/now_playing.dart';

/// Total d'une chaîne sur la période demandée (pour le top).
class ChannelStat {
  const ChannelStat(this.name, this.minutes);
  final String name;
  final int minutes;
}

class WatchStatsService extends ChangeNotifier {
  WatchStatsService._();
  static final WatchStatsService instance = WatchStatsService._();

  static const String _baseKey = 'watch_stats.days';
  static const int _keepDays = 30;
  static const int _maxChannelsPerDay = 40;

  String get _key => '$_baseKey${ProfilesRepository.instance.keySuffix}';

  /// jour (YYYY-MM-DD) → {'t': minutes totales, 'c': {chaîne: minutes}}
  Map<String, Map<String, dynamic>> _days = <String, Map<String, dynamic>>{};
  Timer? _sampler;
  bool _started = false;
  String _loadedForKey = '';

  /// Démarre l'échantillonneur (idempotent). À appeler une fois au boot.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _load();
    // Changement de profil → on relit les stats DU profil actif.
    ProfilesRepository.instance.addListener(_onProfileMaybeChanged);
    _sampler = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  void _onProfileMaybeChanged() {
    if (_loadedForKey != _key) unawaited(_load());
  }

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String raw = prefs.getString(_key) ?? '{}';
      final Map<String, dynamic> j = jsonDecode(raw) as Map<String, dynamic>;
      _days = <String, Map<String, dynamic>>{
        for (final MapEntry<String, dynamic> e in j.entries)
          if (e.value is Map<String, dynamic>)
            e.key: e.value as Map<String, dynamic>,
      };
    } catch (e) {
      debugPrint('[Stats] load: $e');
      _days = <String, Map<String, dynamic>>{};
    }
    _loadedForKey = _key;
    notifyListeners();
  }

  /// +1 minute si une chaîne est en cours de visionnage.
  Future<void> _tick() async {
    final String channel = NowPlaying.instance.current;
    if (channel.isEmpty) return;
    final String day = _dayKey(DateTime.now());
    final Map<String, dynamic> d = _days.putIfAbsent(
        day, () => <String, dynamic>{'t': 0, 'c': <String, dynamic>{}});
    d['t'] = ((d['t'] as num?)?.toInt() ?? 0) + 1;
    final Map<String, dynamic> c =
        (d['c'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    if (c.length < _maxChannelsPerDay || c.containsKey(channel)) {
      c[channel] = ((c[channel] as num?)?.toInt() ?? 0) + 1;
    }
    d['c'] = c;
    _prune();
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(_days));
    } catch (e) {
      debugPrint('[Stats] save: $e');
    }
  }

  /// Garde seulement les [_keepDays] derniers jours (le JSON reste petit).
  void _prune() {
    if (_days.length <= _keepDays) return;
    final List<String> keys = _days.keys.toList()..sort();
    while (keys.length > _keepDays) {
      _days.remove(keys.removeAt(0));
    }
  }

  int _minutesOf(String day) => (_days[day]?['t'] as num?)?.toInt() ?? 0;

  /// Minutes regardées aujourd'hui.
  int get todayMinutes => _minutesOf(_dayKey(DateTime.now()));

  /// Minutes regardées sur les [days] derniers jours (aujourd'hui inclus).
  int minutesLastDays(int days) {
    final DateTime now = DateTime.now();
    int sum = 0;
    for (int i = 0; i < days; i++) {
      sum += _minutesOf(_dayKey(now.subtract(Duration(days: i))));
    }
    return sum;
  }

  /// Totaux quotidiens des 7 derniers jours, du plus ancien à aujourd'hui
  /// (pour les barres de l'écran stats).
  List<int> get last7Daily {
    final DateTime now = DateTime.now();
    return <int>[
      for (int i = 6; i >= 0; i--)
        _minutesOf(_dayKey(now.subtract(Duration(days: i)))),
    ];
  }

  /// Top des chaînes sur les [days] derniers jours.
  List<ChannelStat> topChannels({int days = 7, int limit = 5}) {
    final DateTime now = DateTime.now();
    final Map<String, int> totals = <String, int>{};
    for (int i = 0; i < days; i++) {
      final Map<String, dynamic>? c =
          _days[_dayKey(now.subtract(Duration(days: i)))]?['c']
              as Map<String, dynamic>?;
      if (c == null) continue;
      for (final MapEntry<String, dynamic> e in c.entries) {
        totals[e.key] = (totals[e.key] ?? 0) + ((e.value as num?)?.toInt() ?? 0);
      }
    }
    final List<ChannelStat> list = <ChannelStat>[
      for (final MapEntry<String, int> e in totals.entries)
        ChannelStat(e.key, e.value),
    ]..sort((ChannelStat a, ChannelStat b) => b.minutes.compareTo(a.minutes));
    return list.take(limit).toList(growable: false);
  }

  /// « 2 h 05 » / « 45 min » — libellé humain d'une durée en minutes.
  static String fmt(int minutes) {
    if (minutes < 60) return '$minutes min';
    final int h = minutes ~/ 60;
    final int m = minutes % 60;
    return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
  }
}
