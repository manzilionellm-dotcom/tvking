// =========================================================
//  box_signal_client.dart — Canal long panel → box
// =========================================================
//  La box ouvre GET /api/box/wait et attend (au plus 20 s).
//  Dès qu'un ordre est écrit, la réponse revient. On accuse
//  réception avec POST /api/box/ack. Le secret de la box
//  (X-Device-Secret) est obligatoire : sans lui, 401, et on
//  retombe sur la lecture courte de /api/status.
//
//  Coupure : l'appel échoue, on réessaie plus tard avec le
//  même numéro `after`. Les ordres écrits pendant le trou
//  sont encore là.
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../device/data/device_secret.dart';
import '../domain/box_channel.dart' show safeOrderToken;
import 'subscription_backend.dart';

/// Un ordre, sans secret dedans.
@immutable
class BoxOrder {
  const BoxOrder({
    required this.id,
    required this.kind,
    required this.fleet,
    this.orderId = '',
    this.traceId = '',
  });

  final int id;
  final String kind;

  /// Ordre suivi côté serveur (vide = ancien Worker) et trace du panel.
  final String orderId;
  final String traceId;

  /// Vrai si l'ordre s'adresse à tout le parc (message, thème…).
  final bool fleet;
}

/// Résultat d'une attente. Un seul de ces drapeaux est vrai.
class BoxWaitResult {
  const BoxWaitResult({
    required this.orders,
    required this.timeout,
    required this.unauthorized,
    required this.rateLimited,
    required this.offline,
    required this.raw,
  });

  final List<BoxOrder> orders;
  final bool timeout;
  final bool unauthorized;
  final bool rateLimited;
  final bool offline;

  /// Corps brut, pour vérifier qu'aucun mot de passe n'est dedans.
  final String raw;

  static const BoxWaitResult down = BoxWaitResult(
    orders: <BoxOrder>[],
    timeout: false,
    unauthorized: false,
    rateLimited: false,
    offline: true,
    raw: '',
  );
}

abstract final class BoxSignalClient {
  /// Le serveur garde la connexion 20 s. On laisse 5 s de plus
  /// pour le trajet, puis on considère le réseau coupé.
  static const Duration clientTimeout = Duration(seconds: 25);

  static Future<BoxWaitResult> wait({
    required http.Client client,
    required String mac,
    required int after,
    required int fleetAfter,
    String version = '',
    String build = '',
    int timeoutMs = 20000,
  }) async {
    try {
      final Map<String, String> headers = await DeviceSecret.instance.headers();
      final Uri uri = Uri.parse(
        '$kSubscriptionBaseUrl/api/box/wait/${Uri.encodeComponent(mac)}'
        '?after=$after&fleet_after=$fleetAfter&timeout=$timeoutMs'
        '&v=${Uri.encodeQueryComponent(version)}'
        '&b=${Uri.encodeQueryComponent(build)}',
      );
      final http.Response resp = await client
          .get(uri, headers: headers)
          .timeout(clientTimeout);
      return _read(resp.statusCode, resp.body);
    } catch (e) {
      if (kDebugMode) debugPrint('[Signal] attente : $e');
      return BoxWaitResult.down;
    }
  }

  /// Accusé. `false` si le réseau n'a pas confirmé : on réessaiera,
  /// sans réappliquer les ordres déjà notés localement.
  static Future<bool> ack({
    required http.Client client,
    required String mac,
    required List<int> boxIds,
    required List<int> fleetIds,
  }) async {
    try {
      final Map<String, String> headers =
          await DeviceSecret.instance.headers(jsonBody: true);
      final http.Response resp = await client
          .post(
            Uri.parse(
              '$kSubscriptionBaseUrl/api/box/ack/${Uri.encodeComponent(mac)}',
            ),
            headers: headers,
            body: jsonEncode(<String, Object?>{
              'box': boxIds,
              'fleet': fleetIds,
            }),
          )
          .timeout(const Duration(seconds: 8));
      return resp.statusCode == 200;
    } catch (e) {
      if (kDebugMode) debugPrint('[Signal] accusé : $e');
      return false;
    }
  }

  /// Lecture d'une réponse d'attente longue (exposée pour les tests).
  @visibleForTesting
  static BoxWaitResult readForTest(int status, String body) => _read(status, body);

  static BoxWaitResult _read(int status, String body) {
    if (status == 401) {
      return BoxWaitResult(
        orders: const <BoxOrder>[],
        timeout: false,
        unauthorized: true,
        rateLimited: false,
        offline: false,
        raw: body,
      );
    }
    if (status == 429) {
      return BoxWaitResult(
        orders: const <BoxOrder>[],
        timeout: false,
        unauthorized: false,
        rateLimited: true,
        offline: false,
        raw: body,
      );
    }
    if (status != 200) return BoxWaitResult.down;
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map) return BoxWaitResult.down;
      final Map<String, dynamic> json = decoded as Map<String, dynamic>;
      return BoxWaitResult(
        orders: <BoxOrder>[
          ..._orders(json['box'], fleet: false),
          ..._orders(json['fleet'], fleet: true),
        ],
        timeout: json['timeout'] == true,
        unauthorized: false,
        rateLimited: false,
        offline: false,
        raw: body,
      );
    } catch (_) {
      return BoxWaitResult.down;
    }
  }

  static List<BoxOrder> _orders(Object? raw, {required bool fleet}) {
    if (raw is! List) return const <BoxOrder>[];
    final List<BoxOrder> out = <BoxOrder>[];
    for (final Object? item in raw) {
      if (item is! Map) continue;
      final int id = (item['id'] as num?)?.toInt() ?? 0;
      final String kind = (item['kind'] ?? '').toString();
      if (id <= 0 || kind.isEmpty) continue;
      out.add(BoxOrder(
        id: id,
        kind: kind,
        fleet: fleet,
        orderId: safeOrderToken(item['order_id']),
        traceId: safeOrderToken(item['trace_id']),
      ));
    }
    return out;
  }
}
