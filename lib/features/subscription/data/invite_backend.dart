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

  /// L'abonné PAYÉ [mac] génère un code de partage (2 jours pour l'invité).
  /// Réponse : { ok, code, expires_at, guest_days } ou { ok:false, error }.
  static Future<Map<String, dynamic>?> create(String mac) =>
      _post('/api/invite/create', <String, Object?>{'mac': mac});

  /// Le NOUVEL appareil [mac] active un [code] à 6 chiffres → 2 jours.
  /// Réponse : { ok, guest_until, guest_days } ou { ok:false, error }.
  static Future<Map<String, dynamic>?> redeem(String mac, String code) =>
      _post('/api/invite/redeem', <String, Object?>{'mac': mac, 'code': code});
}
