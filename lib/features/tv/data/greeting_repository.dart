// =========================================================
//  greeting_repository.dart — Accueil personnalisé (ville + météo)
// =========================================================
//  Récupère /api/greeting (ville + température, déduites de l'IP par
//  Cloudflare → AUCUNE permission GPS sur la TV). Best-effort + caché.
// =========================================================
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../subscription/data/subscription_backend.dart';
import 'place_repository.dart';

@immutable
class Greeting {
  const Greeting({
    required this.city,
    required this.country,
    required this.tempC,
    required this.weatherCode,
  });
  final String city;
  final String country;
  final double? tempC;
  final int? weatherCode;

  /// Emoji météo simple (Open-Meteo WMO codes).
  String get emoji {
    final int? c = weatherCode;
    if (c == null) return '';
    if (c == 0) return '☀️';
    if (c <= 2) return '🌤️';
    if (c == 3) return '☁️';
    if (c >= 45 && c <= 48) return '🌫️';
    if (c >= 51 && c <= 67) return '🌧️';
    if (c >= 71 && c <= 77) return '❄️';
    if (c >= 80 && c <= 82) return '🌦️';
    if (c >= 95) return '⛈️';
    return '🌡️';
  }
}

class GreetingRepository {
  GreetingRepository._();
  static final GreetingRepository instance = GreetingRepository._();

  Greeting? _cached;
  Greeting? get current => _cached;

  Future<Greeting?> fetch() async {
    // 1) L'utilisateur a-t-il fixé sa ville ? Si oui, météo EXACTE de cette
    //    ville (Open-Meteo direct) — plus jamais la ville voisine devinée
    //    par l'IP.
    final SavedPlace? place = PlaceRepository.instance.current;
    if (place != null) {
      final Greeting? g = await _fetchForPlace(place);
      if (g != null) _cached = g;
      return _cached;
    }

    // 2) Sinon : détection automatique par IP via le backend (comportement
    //    historique, aucune permission GPS sur la TV).
    try {
      final http.Response resp = await http
          .get(Uri.parse('$kSubscriptionBaseUrl/api/greeting'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return _cached;
      final Object? j = jsonDecode(resp.body);
      if (j is Map) {
        _cached = Greeting(
          city: (j['city'] ?? '').toString(),
          country: (j['country'] ?? '').toString(),
          tempC: (j['tempC'] is num) ? (j['tempC'] as num).toDouble() : null,
          weatherCode: (j['weatherCode'] is num)
              ? (j['weatherCode'] as num).toInt()
              : null,
        );
      }
    } catch (_) {
      // best-effort : on garde le cache éventuel.
    }
    return _cached;
  }

  /// Météo de la ville choisie via Open-Meteo (gratuit, sans clé, mêmes
  /// codes WMO). On garde le nom EXACT choisi par l'utilisateur.
  Future<Greeting?> _fetchForPlace(SavedPlace place) async {
    try {
      final Uri uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${place.latitude}&longitude=${place.longitude}'
        '&current=temperature_2m,weather_code',
      );
      final http.Response resp =
          await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;
      final Object? j = jsonDecode(resp.body);
      if (j is! Map) return null;
      final Object? cur = j['current'];
      double? temp;
      int? code;
      if (cur is Map) {
        final Object? t = cur['temperature_2m'];
        final Object? c = cur['weather_code'];
        if (t is num) temp = t.toDouble();
        if (c is num) code = c.toInt();
      }
      return Greeting(
        city: place.name,
        country: place.country,
        tempC: temp,
        weatherCode: code,
      );
    } catch (_) {
      return null;
    }
  }
}
