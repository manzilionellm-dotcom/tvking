import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// L'essai utilise son adresse dédiée, sans déplacer le heartbeat ni
/// l'activation habituelle. Aucune réponse brute n'est transmise à l'UI.
const String kGoldTrialBaseUrl =
    'https://seven-motion-backend.manzilionel-lm.workers.dev';
const String kGoldTrialPlaylistName = '7 MOTION Essai';

/// Les deux marques partagent le même droit d'essai côté serveur.
bool isGoldTrialPlaylist(String name) =>
    name == kGoldTrialPlaylistName || name == 'Zuno TV Essai';

enum GoldTrialOutcome {
  idle,
  activated,
  alreadyUsed,
  alreadyCustomer,
  inProgress,
  disabled,
  dailyCap,
  rateLimited,
  error,
}

class GoldTrialResult {
  const GoldTrialResult(this.outcome, {this.expire, this.message});
  final GoldTrialOutcome outcome;
  final DateTime? expire;
  final String? message;
}

class GoldTrialIdentity {
  const GoldTrialIdentity({
    required this.mac,
    required this.androidId,
    required this.appVersion,
  });
  final String mac;
  final String androidId;
  final String appVersion;
}

class GoldTrialBackend {
  GoldTrialBackend({
    this.baseUrl = kGoldTrialBaseUrl,
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final String baseUrl;
  final http.Client Function() _clientFactory;
  final Set<http.Client> _pending = <http.Client>{};

  /// Un client par requête permet d'arrêter réellement le réseau au timeout,
  /// au départ de l'écran et au bout des 30 secondes de sondage.
  Future<http.Response> _request(
    Future<http.Response> Function(http.Client) send,
    Duration timeout,
  ) async {
    final http.Client client = _clientFactory();
    _pending.add(client);
    try {
      return await send(client).timeout(timeout);
    } finally {
      _pending.remove(client);
      client.close();
    }
  }

  Future<GoldTrialResult> activate(GoldTrialIdentity identity, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    try {
      final String mac = identity.mac.toUpperCase();
      if (!RegExp(r'^(?:MK|[0-9A-F]{2})(?::[0-9A-F]{2}){5}$').hasMatch(mac) ||
          identity.androidId.trim().isEmpty ||
          identity.appVersion.trim().isEmpty) {
        return const GoldTrialResult(GoldTrialOutcome.error);
      }
      final http.Response response = await _request(
        (http.Client client) => client.post(
          Uri.parse('$baseUrl/api/gold-trial'),
          headers: <String, String>{
            ...headers,
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(<String, String>{
            'mac': mac,
            'android_id': identity.androidId,
            'app_version': identity.appVersion,
          }),
        ),
        const Duration(seconds: 15),
      );
      final Object? body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        return const GoldTrialResult(GoldTrialOutcome.error);
      }
      final String? message = publicMessage(body['message']);
      if (response.statusCode == 201 && body['ok'] == true) {
        final DateTime? expire = parseExpiration(body['expire']);
        return expire == null
            ? const GoldTrialResult(GoldTrialOutcome.error)
            : GoldTrialResult(GoldTrialOutcome.activated, expire: expire, message: message);
      }
      final Object? code = body['error'] is String ? body['error'] : body['code'];
      final GoldTrialOutcome outcome = switch ((response.statusCode, code)) {
        (409, 'trial_already_used') => GoldTrialOutcome.alreadyUsed,
        (409, 'already_customer') => GoldTrialOutcome.alreadyCustomer,
        (409, 'in_progress') => GoldTrialOutcome.inProgress,
        (403, 'trial_disabled') => GoldTrialOutcome.disabled,
        (429, 'daily_cap_reached') => GoldTrialOutcome.dailyCap,
        (429, 'rate_limited') => GoldTrialOutcome.rateLimited,
        _ => GoldTrialOutcome.error,
      };
      return GoldTrialResult(outcome, message: message);
    } catch (_) {
      // Ne jamais afficher une exception brute, une clé ou
      // une adresse fournisseur, même si le serveur renvoie du HTML.
      return const GoldTrialResult(GoldTrialOutcome.error);
    }
  }

  /// Lecture uniquement : le chargement reste assuré par le synchroniseur
  /// existant, avec ses protections contre les doublons et suppressions.
  Future<bool> hasAssignedTrial(
    String mac, {
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    final String deviceMac = mac.toUpperCase();
    if (!RegExp(r'^(?:MK|[0-9A-F]{2})(?::[0-9A-F]{2}){5}$').hasMatch(deviceMac)) return false;
    final http.Response response = await _request(
      (http.Client client) => client.get(
        // Cette route lit le segment brut côté Worker : les deux-points
        // restent littéraux, comme dans le synchroniseur déjà en service.
        Uri.parse('$baseUrl/api/device-source/$deviceMac'),
        headers: <String, String>{'Accept': 'application/json', ...headers},
      ),
      timeout,
    );
    if (response.statusCode != 200) return false;
    final Object? body = jsonDecode(response.body);
    if (body is! Map<String, dynamic> || body['blocked'] != null) return false;
    final Object? sources = body['sources'];
    final List<Object?> candidates = sources is List && sources.isNotEmpty
        ? List<Object?>.from(sources)
        : <Object?>[body['source']];
    return candidates.whereType<Map<String, dynamic>>().any(
          (Map<String, dynamic> source) =>
              source['enabled'] != false &&
              isGoldTrialPlaylist(source['label']?.toString() ?? ''),
        );
  }

  /// Seul « message » est destiné au client. Les autres champs, erreurs
  /// brutes et adresses ne passent jamais dans l'interface. Ce filtre est
  /// une défense supplémentaire ; le Worker doit produire des textes publics.
  static String? publicMessage(Object? value) {
    if (value is! String) return null;
    final String text = value.trim();
    if (text.isEmpty || text.length > 240 ||
        RegExp(r'[<>\x00-\x1f]').hasMatch(text) ||
        RegExp(r'(https?://|www\.|@|strong|cms-8k|manzi|lionel|password|api.?key|secret|provider|[a-z0-9-]+\.(?:net|com|ru|org|dev)\b|\b\d{1,3}(?:\.\d{1,3}){3}\b)',
            caseSensitive: false).hasMatch(text)) {
      return null;
    }
    return text;
  }

  /// Le contrat peut fournir une date ISO ou un timestamp Unix (secondes
  /// ou millisecondes). Une date invalide ne doit pas devenir une fausse fin.
  static DateTime? parseExpiration(Object? value) {
    final num? epoch = value is num
        ? value
        : value is String
            ? num.tryParse(value)
            : null;
    if (epoch != null && epoch.isFinite && epoch > 0) {
      final int ms = (epoch < 100000000000 ? epoch * 1000 : epoch).toInt();
      try {
        return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
      } catch (_) {
        return null;
      }
    }
    return value is String ? DateTime.tryParse(value) : null;
  }

  void cancelPending() {
    for (final http.Client client in _pending.toList()) {
      client.close();
    }
    _pending.clear();
  }
}
