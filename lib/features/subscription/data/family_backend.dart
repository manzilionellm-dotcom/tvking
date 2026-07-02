// =========================================================
//  family_backend.dart — Client de l'ABONNEMENT FAMILLE
// =========================================================
//  Parle aux endpoints /api/family/* du worker (notre backend) :
//    • invite : le PROPRIÉTAIRE (payé) génère un code à 6 chiffres (48 h) ;
//    • join   : un proche tape le code → son appareil est RATTACHÉ ;
//    • info   : vue famille (propriétaire : membres + code ; membre : proprio) ;
//    • remove : détacher un membre (proprio) ou se détacher (membre).
//
//  Tout est best-effort avec timeout court : une panne réseau renvoie null
//  et l'UI affiche un message doux — jamais de blocage.
// =========================================================
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'subscription_backend.dart' show kSubscriptionBaseUrl;

abstract final class FamilyBackend {
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
      if (r.statusCode != 200) return null;
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Génère (ou régénère) le code d'invitation du propriétaire [mac].
  static Future<Map<String, dynamic>?> invite(String mac) =>
      _post('/api/family/invite', <String, Object?>{'mac': mac});

  /// Rattache l'appareil [mac] via le [code] à 6 chiffres.
  static Future<Map<String, dynamic>?> join(String mac, String code) =>
      _post('/api/family/join', <String, Object?>{'mac': mac, 'code': code});

  /// Vue famille pour [mac] (rôle owner/member, membres, code actif).
  static Future<Map<String, dynamic>?> info(String mac) async {
    try {
      final http.Response r = await http
          .get(Uri.parse('$kSubscriptionBaseUrl/api/family/info/$mac'),
              headers: _headers)
          .timeout(_timeout);
      if (r.statusCode != 200) return null;
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Le PROPRIÉTAIRE [mac] nomme un [member] (« Papa », « Maman »…).
  static Future<bool> rename(String mac, String member, String label) async {
    final Map<String, dynamic>? r = await _post(
      '/api/family/rename',
      <String, Object?>{'mac': mac, 'member': member, 'label': label},
    );
    return r != null && r['ok'] == true;
  }

  /// Sans [member] : l'appareil [mac] QUITTE sa famille. Avec [member] :
  /// le propriétaire [mac] détache ce membre.
  static Future<bool> remove(String mac, {String? member}) async {
    final Map<String, dynamic>? r = await _post(
      '/api/family/remove',
      <String, Object?>{'mac': mac, if (member != null) 'member': member},
    );
    return r != null && r['ok'] == true;
  }
}
