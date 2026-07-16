// =========================================================
//  sports_repository.dart — Actu sport + équipes préférées (multi) + alarmes
// =========================================================
//  Source = TheSportsDB via le Worker (proxy + cache 10 min).
//    - search(q)            : rechercher une équipe (picker).
//    - addFavorite/remove   : gérer PLUSIEURS équipes préférées (persisté).
//    - eventsFor(id)        : derniers + prochains matchs (score), maj 10 min.
//    - ALARMES : pour chaque match à venir, un rappel est programmé ~1 h avant
// (NotificationService) → « <équipe> joue bientôt ».
// =========================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/i18n/l10n_now.dart';
import '../../../core/notifications/notification_service.dart';
import '../../subscription/data/subscription_backend.dart' show kSubscriptionBaseUrl;
import '../domain/sport_models.dart';

class SportsEvents {
  const SportsEvents({this.last = const <SportEvent>[], this.next = const <SportEvent>[]});
  final List<SportEvent> last;
  final List<SportEvent> next;
}

class SportsRepository {
  SportsRepository._();
  static final SportsRepository instance = SportsRepository._();

  static const String _kFavV2 = 'sports.favorites.v2'; // tableau JSON d'équipes
  static const String _kFavV1 = 'sports.favorite_team.v1'; // ancien : 1 équipe
  static const Duration _refresh = Duration(minutes: 10);

  final List<SportTeam> _favorites = <SportTeam>[];
  final Map<String, SportsEvents> _eventsByTeam = <String, SportsEvents>{};
  Timer? _timer;
  bool _initialized = false;

  final StreamController<List<SportTeam>> _favController =
      StreamController<List<SportTeam>>.broadcast();
  final StreamController<void> _changesController =
      StreamController<void>.broadcast();

  List<SportTeam> get favorites => List<SportTeam>.unmodifiable(_favorites);
  bool isFavorite(String id) => _favorites.any((SportTeam t) => t.id == id);
  SportsEvents eventsFor(String id) =>
      _eventsByTeam[id] ?? const SportsEvents();
  Stream<List<SportTeam>> get favoritesStream => _favController.stream;
  Stream<void> get changesStream => _changesController.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? v2 = prefs.getString(_kFavV2);
      if (v2 != null && v2.isNotEmpty) {
        final List<dynamic> list = jsonDecode(v2) as List<dynamic>;
        _favorites
          ..clear()
          ..addAll(list
              .whereType<Map<String, dynamic>>()
              .map(SportTeam.fromJson)
              .where((SportTeam t) => t.id.isNotEmpty));
      } else {
        // Migration depuis l'ancienne unique équipe.
        final String? v1 = prefs.getString(_kFavV1);
        if (v1 != null && v1.isNotEmpty) {
          _favorites.add(
              SportTeam.fromJson(jsonDecode(v1) as Map<String, dynamic>));
          await _save(prefs);
          await prefs.remove(_kFavV1);
        }
      }
    } catch (_) {}
    _emitFav();
    if (_favorites.isNotEmpty) {
      unawaited(_fetchAll());
      _startTimer();
    }
  }

  Future<List<SportTeam>> search(String q) async {
    final String query = q.trim();
    if (query.length < 2) return const <SportTeam>[];
    try {
      final http.Response resp = await http
          .get(Uri.parse('$kSubscriptionBaseUrl/api/sports/search?q=${Uri.encodeQueryComponent(query)}'),
              headers: const <String, String>{'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return const <SportTeam>[];
      final Map<String, dynamic> body = jsonDecode(resp.body) as Map<String, dynamic>;
      final List<dynamic> teams = (body['teams'] as List<dynamic>?) ?? const <dynamic>[];
      return teams
          .whereType<Map<String, dynamic>>()
          .map(SportTeam.fromJson)
          .where((SportTeam t) => t.id.isNotEmpty && t.name.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      if (kDebugMode) debugPrint('[Sports] search error: $e');
      return const <SportTeam>[];
    }
  }

  Future<void> addFavorite(SportTeam team) async {
    if (isFavorite(team.id)) return;
    _favorites.add(team);
    try {
      await _save(await SharedPreferences.getInstance());
    } catch (_) {}
    _emitFav();
    await _fetchTeam(team.id);
    _startTimer();
  }

  Future<void> removeFavorite(String id) async {
    _favorites.removeWhere((SportTeam t) => t.id == id);
    _eventsByTeam.remove(id);
    try {
      await _save(await SharedPreferences.getInstance());
    } catch (_) {}
    _emitFav();
    if (!_changesController.isClosed) _changesController.add(null);
    if (_favorites.isEmpty) _timer?.cancel();
  }

  Future<void> _save(SharedPreferences prefs) async {
    await prefs.setString(
        _kFavV2,
        jsonEncode(_favorites.map((SportTeam t) => t.toJson()).toList()));
  }

  void _emitFav() {
    if (!_favController.isClosed) {
      _favController.add(List<SportTeam>.unmodifiable(_favorites));
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_refresh, (_) => _fetchAll());
  }

  Future<void> _fetchAll() async {
    for (final SportTeam t in List<SportTeam>.from(_favorites)) {
      await _fetchTeam(t.id);
    }
  }

  Future<void> _fetchTeam(String id) async {
    SportTeam? team;
    for (final SportTeam t in _favorites) {
      if (t.id == id) {
        team = t;
        break;
      }
    }
    if (team == null) return;
    try {
      final http.Response resp = await http
          .get(Uri.parse('$kSubscriptionBaseUrl/api/sports/team/${Uri.encodeComponent(id)}'),
              headers: const <String, String>{'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return;
      final Map<String, dynamic> body = jsonDecode(resp.body) as Map<String, dynamic>;
      List<SportEvent> parse(String key) =>
          ((body[key] as List<dynamic>?) ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(SportEvent.fromJson)
              .toList(growable: false);
      final SportsEvents ev = SportsEvents(last: parse('last'), next: parse('next'));
      _eventsByTeam[id] = ev;
      if (!_changesController.isClosed) _changesController.add(null);
      unawaited(_scheduleReminders(team, ev.next));
    } catch (e) {
      if (kDebugMode) debugPrint('[Sports] events error: $e');
    }
  }

  // ALARME ~1 h avant chaque match à venir. Idempotent (le service dédoublonne
  // par id stable) → re-planifier toutes les 10 min ne crée pas de doublons.
  Future<void> _scheduleReminders(SportTeam team, List<SportEvent> next) async {
    for (final SportEvent ev in next) {
      final DateTime? start = ev.startsAt;
      if (start == null || start.isBefore(DateTime.now())) continue;
      try {
        // Titre traduit via l10nNow : la notification est (re)planifiée
        // toutes les 10 min, donc le texte suit la langue active.
        await NotificationService.instance.scheduleProgramReminder(
          channelId: 'sport_${team.id}_${ev.id}',
          channelName: team.name,
          title: l10nNow.sportsTeamPlaysSoon(team.name),
          startMs: start.millisecondsSinceEpoch,
          leadMinutes: 60,
        );
        // COUP D'ENVOI : une 2e notification À L'HEURE EXACTE du match
        // (« C'est parti ! France – Belgique ») — celle qu'on attend
        // vraiment quand on a oublié la première. Id distinct (_ko) →
        // le dédoublonnage du service laisse coexister les deux rappels.
        final String affiche = (ev.home.isNotEmpty && ev.away.isNotEmpty)
            ? '${ev.home} – ${ev.away}'
            : team.name;
        await NotificationService.instance.scheduleProgramReminder(
          channelId: 'sport_${team.id}_${ev.id}_ko',
          channelName: team.name,
          title: l10nNow.sportsKickoff(affiche),
          startMs: start.millisecondsSinceEpoch,
          leadMinutes: 0,
        );
      } catch (_) {}
    }
  }
}
