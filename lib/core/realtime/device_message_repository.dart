// =========================================================
//  device_message_repository.dart — Boîte de réception par appareil
// =========================================================
//  Relève les messages PERSISTANTS déposés depuis le panel pour CETTE
//  MAC (GET /api/device-messages/:mac). Livrés même si l'appareil était
//  hors ligne au moment de l'envoi : ils attendent la prochaine ouverture
//  (façon WhatsApp). Le serveur les marque « livrés » à la lecture (accusé
//  de réception visible côté panel), donc on ne les rejoue pas.
//
//  Affichage : on réutilise la bannière admin (AdminMessageBanner) via
//  RealtimeSyncService.showAdminMessage — même look que les messages temps
//  réel. Si plusieurs messages attendent, on les enchaîne.
//
//  FAIL-OPEN ABSOLU : toute erreur réseau/parse → on ne montre rien, l'app
//  continue normalement. Jamais d'exception sortante.
// =========================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../features/device/data/device_identity.dart';
import '../backend/backend_hosts.dart';
import 'realtime_sync_service.dart';

abstract final class DeviceMessageRepository {
  /// Empêche deux relèves simultanées (boot + resume rapprochés).
  static bool _busy = false;

  /// Relève la boîte et affiche les messages en attente. À appeler au boot
  /// et à chaque retour au premier plan. Ne throw jamais.
  static Future<void> fetchAndShow() async {
    if (_busy) return;
    _busy = true;
    try {
      final String mac = await DeviceIdentity.instance.mac;
      final String base = BackendHosts.current;
      final http.Response r = await http
          .get(Uri.parse('$base/api/device-messages/${Uri.encodeComponent(mac)}'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final Object? decoded = jsonDecode(r.body);
      if (decoded is! Map) return;
      final Object? items = decoded['items'];
      if (items is! List || items.isEmpty) return;
      // Enchaîne l'affichage : chaque message reste sa durée, puis le suivant.
      unawaited(_showSequentially(items));
    } catch (e) {
      if (kDebugMode) debugPrint('[DeviceMsg] fetch error: $e');
    } finally {
      _busy = false;
    }
  }

  static Future<void> _showSequentially(List<Object?> items) async {
    for (final Object? raw in items) {
      if (raw is! Map) continue;
      final int dur = ((raw['durationSec'] as num?)?.toInt() ?? 45).clamp(3, 120);
      final String kindRaw = (raw['kind'] ?? 'info').toString();
      final String kind =
          const <String>['info', 'success', 'warning'].contains(kindRaw)
              ? kindRaw
              : 'info';
      final AdminMessage msg = AdminMessage(
        id: 'devmsg-${raw['id']}',
        title: (raw['title'] ?? '').toString(),
        body: (raw['body'] ?? '').toString(),
        kind: kind,
        durationSec: dur,
      );
      RealtimeSyncService.instance.showAdminMessage(msg);
      // Laisse le message vivre sa durée avant d'afficher le suivant.
      await Future<void>.delayed(Duration(seconds: dur + 1));
    }
  }
}
