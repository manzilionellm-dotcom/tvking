// =========================================================
//  sports_repository.dart — Actu sport + équipe préférée
// =========================================================
//  Source = TheSportsDB, MAIS toujours via ton Worker (proxy + cache 10 min) :
//  l'app n'appelle jamais l'API tierce directement.
//    - search(q)            : rechercher une équipe (picker).
//    - setFavorite(team)    : choisir SON équipe (persisté).
//    - eventsStream         : derniers + prochains matchs (avec score),
//                             rafraîchis automatiquement toutes les 10 min.
// =========================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

  static const String _kFavKey = 'sports.favorite_team.v1';
  static const Duration _refresh = Duration(minutes: 10);

  SportTeam? _favorite;
  SportsEvents _events = const SportsEvents();
  Timer? _timer;
  bool _initialized = false;

  final StreamController<SportTeam?> _favController =
      StreamController<SportTeam?>.broadcast();
  final StreamController<SportsEvents> _eventsController =
      StreamController<SportsEvents>.broadcast();

  SportTeam? get favorite => _favorite;
  SportsEvents get events => _events;
  Stream<SportTeam?> get favoriteStream => _favController.stream;
  Stream<SportsEvents> get eventsStream => _eventsController.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_kFavKey);
      if (raw != null && raw.isNotEmpty) {
        _favorite = SportTeam.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
    if (!_favController.isClosed) _favController.add(_favorite);
    if (_favorite != null) {
      unawaited(_fetchEvents());
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

  Future<void> setFavorite(SportTeam team) async {
    _favorite = team;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kFavKey, jsonEncode(team.toJson()));
    } catch (_) {}
    if (!_favController.isClosed) _favController.add(_favorite);
    _events = const SportsEvents();
    if (!_eventsController.isClosed) _eventsController.add(_events);
    await _fetchEvents();
    _startTimer();
  }

  Future<void> clearFavorite() async {
    _favorite = null;
    _events = const SportsEvents();
    _timer?.cancel();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kFavKey);
    } catch (_) {}
    if (!_favController.isClosed) _favController.add(null);
    if (!_eventsController.isClosed) _eventsController.add(_events);
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_refresh, (_) => _fetchEvents());
  }

  Future<void> _fetchEvents() async {
    final SportTeam? fav = _favorite;
    if (fav == null) return;
    try {
      final http.Response resp = await http
          .get(Uri.parse('$kSubscriptionBaseUrl/api/sports/team/${Uri.encodeComponent(fav.id)}'),
              headers: const <String, String>{'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return;
      final Map<String, dynamic> body = jsonDecode(resp.body) as Map<String, dynamic>;
      List<SportEvent> parse(String key) =>
          ((body[key] as List<dynamic>?) ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(SportEvent.fromJson)
              .toList(growable: false);
      _events = SportsEvents(last: parse('last'), next: parse('next'));
      if (!_eventsController.isClosed) _eventsController.add(_events);
    } catch (e) {
      if (kDebugMode) debugPrint('[Sports] events error: $e');
    }
  }
}
