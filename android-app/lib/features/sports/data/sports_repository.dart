// =========================================================
//  sports_repository.dart — Actu sport + équipes préférées (multi) + alarmes
// =========================================================
//  Source = TheSportsDB via le Worker (proxy + cache 10 min).
//    - search(q)            : rechercher une équipe (picker).
//    - addFavorite/remove   : gérer PLUSIEURS équipes préférées (persisté).
//    - eventsFor(id)        : derniers + prochains matchs (score), maj 10 min.
//    - ALARMES : pour chaque match à venir, un rappel est programmé ~1 h avant
//      (NotificationService) → « ⚽ <équipe> joue bientôt ».
// =========================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/app/repair_flags.dart';
import '../../../core/blackbox/black_box.dart';
import '../../../core/notifications/notification_service.dart';
import '../../subscription/data/subscription_backend.dart' show kSubscriptionBaseUrl;
import '../domain/sport_models.dart';

class SportsEvents {
  const SportsEvents({this.last = const <SportEvent>[], this.next = const <SportEvent>[],
    this.loading = false, this.failure});
  final List<SportEvent> last;
  final List<SportEvent> next;
  final bool loading;
  final SportsFailure? failure;
}

enum SportsFailureKind { timeout, network, http, invalidResponse, unavailable }

/// Une raison sans adresse, corps serveur, requête ou exception brute.
class SportsFailure implements Exception {
  const SportsFailure(this.kind, {this.statusCode});
  final SportsFailureKind kind;
  final int? statusCode;

  String get diagnostic => switch (kind) {
    SportsFailureKind.timeout => 'délai dépassé (20 s)',
    SportsFailureKind.network => 'connexion au service impossible',
    SportsFailureKind.http => 'service indisponible (HTTP $statusCode)',
    SportsFailureKind.invalidResponse => 'réponse du service illisible',
    SportsFailureKind.unavailable => 'chargement échoué',
  };
}

class SportsSearchResult {
  const SportsSearchResult({this.teams = const <SportTeam>[], this.failure});
  final List<SportTeam> teams;
  final SportsFailure? failure;
}

class SportsRepository {
  SportsRepository._() : _baseUri = Uri.parse(kSubscriptionBaseUrl);

  /// Le test passe par un vrai serveur HTTP local ; seul son emplacement change.
  @visibleForTesting
  SportsRepository.forTesting(Uri baseUri) : _baseUri = baseUri;

  static final SportsRepository instance = SportsRepository._();

  final Uri _baseUri;

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

  Future<List<SportTeam>> search(String q) async => (await searchResult(q)).teams;

  /// L'absence d'équipe et une panne réseau sont deux résultats distincts.
  Future<SportsSearchResult> searchResult(String q) async {
    final String query = q.trim();
    if (query.length < 2) return const SportsSearchResult();
    final bool legacy = RepairFlags.sportsNetworkLegacy;
    final Stopwatch elapsed = Stopwatch()..start();
    try {
      final http.Response resp = await _get(_baseUri.resolve('/api/sports/search')
          .replace(queryParameters: <String, String>{'q': query}), legacy);
      final Map<String, dynamic> body = _body(resp);
      final List<SportTeam> teams = _list(body, 'teams', legacy)
          .whereType<Map<String, dynamic>>()
          .map(SportTeam.fromJson)
          .where((SportTeam t) => t.id.isNotEmpty && t.name.isNotEmpty)
          .toList(growable: false);
      if (!legacy) BlackBox.instance.info('SPORT',
          'recherche chargée en ${elapsed.elapsedMilliseconds} ms (${teams.length} équipe(s))');
      return SportsSearchResult(teams: teams);
    } catch (e) {
      return SportsSearchResult(failure: _failure(e, 'recherche', legacy));
    }
  }

  /// Un seul appel, borné. Fermer le client rend aussi la connexion lorsque
  /// le délai expire ; Future.timeout seul laisse le téléchargement continuer.
  Future<http.Response> _get(Uri uri, bool legacy) async {
    const Map<String, String> headers = <String, String>{'Accept': 'application/json'};
    if (legacy) {
      final http.Response response = await http.get(uri, headers: headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) throw SportsFailure(
          SportsFailureKind.http, statusCode: response.statusCode);
      return response;
    }
    final http.Client client = http.Client();
    try {
      final http.Response response = await client.get(uri, headers: headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw SportsFailure(
          SportsFailureKind.http, statusCode: response.statusCode);
      return response;
    } finally {
      client.close();
    }
  }

  Map<String, dynamic> _body(http.Response response) {
    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Objet Sport attendu');
    }
    return decoded;
  }

  List<dynamic> _list(Map<String, dynamic> body, String key, bool legacy) {
    final dynamic value = body[key];
    if (value == null && legacy) return const <dynamic>[];
    if (value is! List<dynamic>) throw const FormatException('Liste Sport attendue');
    return value;
  }

  SportsFailure? _failure(Object error, String operation, bool legacy) {
    if (legacy) {
      if (kDebugMode) debugPrint('[Sports] $operation échouée');
      return null;
    }
    final SportsFailure failure = error is SportsFailure ? error
        : SportsFailure(error is TimeoutException ? SportsFailureKind.timeout
            : error is http.ClientException ? SportsFailureKind.network
            : error is FormatException || error is TypeError
                ? SportsFailureKind.invalidResponse : SportsFailureKind.unavailable);
    BlackBox.instance.warn('SPORT', '$operation : ${failure.diagnostic}');
    return failure;
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
    final bool legacy = RepairFlags.sportsNetworkLegacy;
    final SportsEvents previous = eventsFor(id);
    if (!legacy) {
      _eventsByTeam[id] = SportsEvents(last: previous.last, next: previous.next, loading: true);
      if (!_changesController.isClosed) _changesController.add(null);
    }
    final Stopwatch elapsed = Stopwatch()..start();
    try {
      final http.Response resp = await _get(
          _baseUri.resolve('/api/sports/team/${Uri.encodeComponent(id)}'), legacy);
      final Map<String, dynamic> body = _body(resp);
      List<SportEvent> parse(String key) =>
          _list(body, key, legacy)
              .whereType<Map<String, dynamic>>()
              .map(SportEvent.fromJson)
              .toList(growable: false);
      final SportsEvents ev = SportsEvents(last: parse('last'), next: parse('next'));
      _eventsByTeam[id] = ev;
      if (!legacy) BlackBox.instance.info('SPORT',
          'matchs chargés en ${elapsed.elapsedMilliseconds} ms (${ev.last.length} passé(s), ${ev.next.length} à venir)');
      if (!_changesController.isClosed) _changesController.add(null);
      unawaited(_scheduleReminders(team, ev.next));
    } catch (e) {
      final SportsFailure? failure = _failure(e, 'matchs', legacy);
      if (failure != null && isFavorite(id)) {
        _eventsByTeam[id] = SportsEvents(last: previous.last, next: previous.next, failure: failure);
        if (!_changesController.isClosed) _changesController.add(null);
      }
    }
  }

  /// Le nouvel appel part seulement lorsque le client choisit « Réessayer ».
  Future<void> refreshTeam(String id) => _fetchTeam(id);

  // ALARME ~1 h avant chaque match à venir. Idempotent (le service dédoublonne
  // par id stable) → re-planifier toutes les 10 min ne crée pas de doublons.
  Future<void> _scheduleReminders(SportTeam team, List<SportEvent> next) async {
    for (final SportEvent ev in next) {
      final DateTime? start = ev.startsAt;
      if (start == null || start.isBefore(DateTime.now())) continue;
      try {
        await NotificationService.instance.scheduleProgramReminder(
          channelId: 'sport_${team.id}_${ev.id}',
          channelName: team.name,
          title: '⚽ ${team.name} joue bientôt',
          startMs: start.millisecondsSinceEpoch,
          leadMinutes: 60,
        );
      } catch (_) {}
    }
  }
}
