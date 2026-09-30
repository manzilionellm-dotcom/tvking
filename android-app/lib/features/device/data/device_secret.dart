// =========================================================
//  device_secret.dart — Preuve que la requête vient de CETTE box
// =========================================================
//  La MAC est affichée sur l'accueil. Elle ne doit plus suffire à
//  lire les codes IPTV ni la sauvegarde cloud.
//
//  Au premier lancement de cette version, on tire un secret au
//  hasard, on le garde dans les préférences (il survit à une mise
//  à jour, pas à une désinstallation), et on l'envoie au Worker
//  avec l'identifiant Android. Le Worker n'en garde que l'empreinte.
//
//  Après une réinstallation, l'identifiant Android est le même :
//  le Worker accepte le nouveau secret. Quelqu'un qui n'a vu que
//  la MAC ne peut pas le faire.
// =========================================================

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../subscription/data/subscription_backend.dart';
import 'device_identity.dart';

/// Nom du header attendu par le Worker. À garder identique à
/// `DEVICE_SECRET_HEADER` dans worker.js.
const String kDeviceSecretHeader = 'X-Device-Secret';

class DeviceSecret {
  DeviceSecret._();
  static final DeviceSecret instance = DeviceSecret._();

  static const String _kSecret = 'device.secret.v1';

  /// Secret local, créé au besoin. Jamais vide une fois cette
  /// méthode résolue.
  Future<String> getOrCreate() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? existing = prefs.getString(_kSecret);
    if (existing != null && existing.length >= 32) return existing;
    final Random rnd = Random.secure();
    final List<int> bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    final String secret = base64Url.encode(bytes);
    await prefs.setString(_kSecret, secret);
    return secret;
  }

  /// En-têtes à poser sur device-source, backup, et le diagnostic.
  Future<Map<String, String>> headers({bool jsonBody = false}) async {
    final String secret = await getOrCreate();
    return <String, String>{
      'Accept': 'application/json',
      if (jsonBody) 'Content-Type': 'application/json',
      kDeviceSecretHeader: secret,
    };
  }

  /// Déclare le secret au Worker. Best-effort : un échec réseau ne
  /// bloque pas la lecture (l'ancien logiciel est encore accepté
  /// tant que le serveur n'a pas d'empreinte).
  Future<void> enroll(String mac) async {
    try {
      if (!mac.startsWith('MK:')) return;
      final String secret = await getOrCreate();
      final String androidId = await DeviceIdentity.instance.androidId();
      await http
          .post(
            Uri.parse('$kSubscriptionBaseUrl/api/device-proof'),
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(<String, String>{
              'mac': mac,
              'androidId': androidId,
              'secret': secret,
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      if (kDebugMode) debugPrint('[DeviceSecret] enroll: $e');
    }
  }
}
