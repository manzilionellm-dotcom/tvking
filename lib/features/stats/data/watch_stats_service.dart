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
  bool _started = false;
  String _loadedForKey = '';

  /// Démarre l'échantillonneur (idempotent). À appeler une fois au boot.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _load();
    // Changement de profil → on relit les stats DU profil actif.
    ProfilesRepository.instance.addListener(_onProfileMaybeChanged);
    // Échantillonneur à vie d'app (singleton, démarrage idempotent) :
    // le Timer n'est volontairement jamais annulé, inutile de le garder.
    Timer.periodic(const Duration(minutes: 1), (_) => _tick());
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

  /// Minutes de visionnage CONSÉCUTIVES (remis à zéro dès qu'on quitte le
  /// lecteur). Sert au petit mot « Pense à toi » après une longue séance.
  int _streak = 0;
  int get continuousMinutes => _streak;

  /// +1 minute si une chaîne est en cours de visionnage.
  Future<void> _tick() async {
    final String channel = NowPlaying.instance.current;
    if (channel.isEmpty) {
      _streak = 0;
      return;
    }
    _streak += 1;
    final DateTime now = DateTime.now();
    final String day = _dayKey(now);
    final Map<String, dynamic> d = _days.putIfAbsent(
        day, () => <String, dynamic>{'t': 0, 'c': <String, dynamic>{}});
    d['t'] = ((d['t'] as num?)?.toInt() ?? 0) + 1;
    final Map<String, dynamic> c =
        (d['c'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    if (c.length < _maxChannelsPerDay || c.containsKey(channel)) {
      c[channel] = ((c[channel] as num?)?.toInt() ?? 0) + 1;
    }
    d['c'] = c;
    // MOMENT DE LA JOURNÉE : minute rangée dans son créneau (matin /
    // après-midi / soirée / nuit) → l'app apprend QUAND ce profil regarde.
    final Map<String, dynamic> h =
        (d['h'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final String slot = _slotOf(now.hour);
    h[slot] = ((h[slot] as num?)?.toInt() ?? 0) + 1;
    d['h'] = h;
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

  /// Créneau d'une heure de la journée : m(atin) 5-12, a(près-midi) 12-18,
  /// s(oirée) 18-23, n(uit) 23-5.
  static String _slotOf(int hour) {
    if (hour >= 5 && hour < 12) return 'm';
    if (hour >= 12 && hour < 18) return 'a';
    if (hour >= 18 && hour < 23) return 's';
    return 'n';
  }

  /// « Ton moment télé » sur 14 jours → CLÉ NEUTRE 'm'/'a'/'s'/'n' (l'écran
  /// la traduit). `null` tant qu'il n'y a pas au moins 1 h de données (on ne
  /// devine pas, on constate).
  String? favoriteMomentKey({int days = 14}) {
    final DateTime now = DateTime.now();
    final Map<String, int> slots = <String, int>{};
    for (int i = 0; i < days; i++) {
      final Map<String, dynamic>? h =
          _days[_dayKey(now.subtract(Duration(days: i)))]?['h']
              as Map<String, dynamic>?;
      if (h == null) continue;
      for (final MapEntry<String, dynamic> e in h.entries) {
        slots[e.key] = (slots[e.key] ?? 0) + ((e.value as num?)?.toInt() ?? 0);
      }
    }
    final int total = slots.values.fold(0, (int a, int b) => a + b);
    if (total < 60) return null;
    return (slots.entries.toList()
          ..sort((MapEntry<String, int> a, MapEntry<String, int> b) =>
              b.value.compareTo(a.value)))
        .first
        .key;
  }

  /// « Ton jour le plus télé » sur 28 jours → NUMÉRO de jour 1(lundi)..7
  /// (l'écran le traduit). `null` sous 2 h de données.
  int? favoriteWeekday({int days = 28}) {
    final DateTime now = DateTime.now();
    final Map<int, int> byWeekday = <int, int>{};
    int total = 0;
    for (int i = 0; i < days; i++) {
      final DateTime d = now.subtract(Duration(days: i));
      final int mins = _minutesOf(_dayKey(d));
      if (mins <= 0) continue;
      byWeekday[d.weekday] = (byWeekday[d.weekday] ?? 0) + mins;
      total += mins;
    }
    if (total < 120 || byWeekday.isEmpty) return null;
    return (byWeekday.entries.toList()
          ..sort((MapEntry<int, int> a, MapEntry<int, int> b) =>
              b.value.compareTo(a.value)))
        .first
        .key;
  }
}
