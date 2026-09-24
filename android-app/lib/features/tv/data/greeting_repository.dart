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
}
