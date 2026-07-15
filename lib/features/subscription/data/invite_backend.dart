// =========================================================
//  invite_backend.dart — Client du PASS PARTAGE (« regarder ensemble »)
// =========================================================
//  Parle aux endpoints /api/invite/* du worker :
//    • create : un abonné PAYÉ génère un code à 6 chiffres (valable 48 h) ;
//    • redeem : un NOUVEL appareil tape le code → 2 jours d'accès, UNE fois
//      à vie, puis il doit payer.
//
//  Best-effort avec timeout court : une panne réseau renvoie null et l'UI
//  affiche un message doux — jamais de blocage.
// =========================================================
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'subscription_backend.dart' show kSubscriptionBaseUrl;

abstract final class InviteBackend {
  static const Duration _timeout = Duration(seconds: 8);
  static const Map<String, String> _headers = <String, String>{
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  static Future<Map<String, dynamic>?> _post(
      String path, Map<String, Object?> body) async {
    try {
      final http.Response r = await http
          .post(Uri.parse('$kSubscriptionBaseUrl$path'),
              headers: _headers, body: jsonEncode(body))
          .timeout(_timeout);
      // On renvoie le corps même sur 4xx : l'UI a besoin du champ `error`
      // (not_paid, code_used, already_used_once…) pour afficher le bon message.
      final Object? decoded = jsonDecode(r.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// L'abonné PAYÉ [mac] génère un code de partage. [hours] = 24 ou 48 ;
  /// [channel] = la chaîne partagée (name/streamUrl/logoUrl/category) ;
  /// [mode] = 'together' | 'test'.
  /// Réponse : { ok, code, hours, mode, channel, weekly_used, weekly_quota }.
  static Future<Map<String, dynamic>?> create(
    String mac, {
    int hours = 48,
    Map<String, Object?>? channel,
    String mode = 'together',
  }) =>
      _post('/api/invite/create', <String, Object?>{
        'mac': mac,
        'hours': hours,
        'mode': mode,
        if (channel != null) 'channel': channel,
      });

  /// Le NOUVEL appareil [mac] active un [code] à 6 chiffres.
  /// Réponse : { ok, guest_until, hours, mode, channel, inviter } ou {error}.
  static Future<Map<String, dynamic>?> redeem(String mac, String code) =>
      _post('/api/invite/redeem', <String, Object?>{'mac': mac, 'code': code});

  /// L'abonné PAYÉ [mac] active DIRECTEMENT l'appareil [guestMac] par sa MAC
  /// (activation poussée — rien à taper côté invité).
  static Future<Map<String, dynamic>?> grant(
    String mac,
    String guestMac, {
    int hours = 48,
    Map<String, Object?>? channel,
    String mode = 'together',
  }) =>
      _post('/api/invite/grant', <String, Object?>{
        'mac': mac,
        'guest_mac': guestMac,
        'hours': hours,
        'mode': mode,
        if (channel != null) 'channel': channel,
      });

  /// « Entre MES appareils » : déplace l'abonnement PAYÉ de [mac] vers
  /// [targetMac] (l'ancien passe en pause — jamais en simultané).
  static Future<Map<String, dynamic>?> transfer(String mac, String targetMac) =>
      _post('/api/invite/transfer',
          <String, Object?>{'mac': mac, 'target_mac': targetMac});

  /// L'appareil INVITÉ [mac] récupère SA chaîne partagée + temps restant.
  /// Réponse : { active, invited, ms_left, mode, inviter, channel }.
  static Future<Map<String, dynamic>?> mine(String mac) async {
    try {
      final http.Response r = await http
          .get(Uri.parse('$kSubscriptionBaseUrl/api/invite/mine/$mac'),
              headers: _headers)
          .timeout(_timeout);
      final Object? decoded = jsonDecode(r.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }
}
