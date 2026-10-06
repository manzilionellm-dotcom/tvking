// =========================================================
//  order_ack_client.dart — Envoi des accusés d'ordres au Worker
// =========================================================
//  POST /api/box/ack/:mac { orders: [ … ] } (voir domain/order_ack.dart).
//  Le serveur est idempotent : un même accusé reçu deux fois ne change
//  rien. On réessaie donc sans risque, trois fois au plus (1 s, 3 s, 9 s),
//  uniquement sur coupure réseau ou 5xx ; une réponse 4xx est définitive
//  (ordre inconnu, accusé refusé) et journalisée.
//  Repli `zuno.ack.off` : aucun accusé envoyé (ancien comportement).
// =========================================================
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/app/repair_flags.dart';
import '../../../core/blackbox/black_box.dart';
import '../../device/data/device_secret.dart';
import 'subscription_backend.dart';

abstract final class OrderAckClient {
  static const List<Duration> retryDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 9),
  ];

  /// Rend vrai si le serveur a confirmé (200).
  static Future<bool> send(
    String mac,
    List<Map<String, Object?>> orders, {
    http.Client? client,
    List<Duration> delays = retryDelays,
  }) async {
    if (RepairFlags.orderAckOff || orders.isEmpty) return false;
    final http.Client c = client ?? http.Client();
    try {
      for (int attempt = 0; attempt <= delays.length; attempt++) {
        int status = 0;
        try {
          final Map<String, String> headers = await DeviceSecret.instance.headers(jsonBody: true);
          final http.Response resp = await c
              .post(
                Uri.parse('$kSubscriptionBaseUrl/api/box/ack/${Uri.encodeComponent(mac)}'),
                headers: headers,
                body: jsonEncode(<String, Object?>{'orders': orders}),
              )
              .timeout(const Duration(seconds: 8));
          status = resp.statusCode;
          if (status == 200) return true;
          if (status >= 400 && status < 500) {
            BlackBox.instance.warn('PANEL', 'accusé refusé par le serveur (HTTP $status)');
            return false;
          }
        } catch (_) {
          status = 0;
        }
        if (attempt < delays.length) await Future<void>.delayed(delays[attempt]);
      }
      BlackBox.instance.warn('PANEL', 'accusé non transmis après ${delays.length + 1} essais');
      return false;
    } finally {
      if (client == null) c.close();
    }
  }
}
