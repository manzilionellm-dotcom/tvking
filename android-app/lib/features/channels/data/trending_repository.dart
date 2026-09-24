// =========================================================
//  trending_repository.dart — « Tendances en direct »
// =========================================================
//  Fonction premium (preuve sociale temps réel) : on récupère du backend la
//  liste des chaînes les PLUS REGARDÉES en ce moment par l'ensemble des
//  appareils en ligne (endpoint public GET /api/trending, agrégation de la
//  table `presence`). On expose les NOMS de chaînes, dans l'ordre de
//  popularité — l'UI les fait correspondre aux chaînes de la playlist locale
//  (par `cleanName`).
//
//  100 % hors du chemin vidéo : on ne touche pas au lecteur, juste à des
//  données affichées dans une rangée/catégorie du Direct.
// =========================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../subscription/data/subscription_backend.dart' show kSubscriptionBaseUrl;

class TrendingRepository {
  TrendingRepository._();
  static final TrendingRepository instance = TrendingRepository._();

  final StreamController<List<String>> _controller =
      StreamController<List<String>>.broadcast();

  /// Noms de chaînes tendance, du plus regardé au moins regardé.
  List<String> _names = const <String>[];
  Timer? _timer;

  Stream<List<String>> get stream => _controller.stream;
  List<String> get current => _names;

  /// Démarre le rafraîchissement périodique (idempotent). À appeler quand on
  /// ouvre l'écran Direct.
  void start() {
    _fetch();
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => _fetch());
  }

  /// Arrête le rafraîchissement (quand on quitte l'écran).
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _fetch() async {
    try {
      final http.Response resp = await http
          .get(Uri.parse('$kSubscriptionBaseUrl/api/trending'),
              headers: const <String, String>{'Accept': 'application/json'})
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return;
      final Map<String, dynamic> body =
          jsonDecode(resp.body) as Map<String, dynamic>;
      final List<dynamic> items =
          (body['items'] as List<dynamic>?) ?? const <dynamic>[];
      final List<String> names = <String>[];
      for (final dynamic e in items) {
        if (e is Map) {
          final String name = '${e['channel'] ?? ''}'.trim();
          if (name.isNotEmpty) names.add(name);
        }
      }
      _names = names;
      if (!_controller.isClosed) _controller.add(_names);
    } catch (e) {
      if (kDebugMode) debugPrint('[Trending] fetch error: $e');
    }
  }
}
