// Adaptateurs configurables. Ils n'altèrent ni SubscriptionState ni les
// licences du panel. Aucun achat ni micro ne se déclenche au démarrage.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'mobile_services.dart';

class StoreBridge {
  static const String publicKey = String.fromEnvironment(
    'REVENUECAT_PUBLIC_KEY',
  );
  static bool _ready = false;
  static Future<void> _configure() async {
    if (publicKey.isEmpty) throw StateError('Achats intégrés non configurés.');
    if (!_ready) {
      await Purchases.configure(PurchasesConfiguration(publicKey));
      _ready = true;
    }
  }

  static Future<CustomerInfo> customerInfo() async {
    await _configure();
    return Purchases.getCustomerInfo();
  }

  static Future<CustomerInfo> restore() async {
    await _configure();
    return Purchases.restorePurchases();
  }

  static Future<Offerings> offers() async {
    await _configure();
    return Purchases.getOfferings();
  }
  // Pas de bouton d'achat avant le raccordement vérifié des droits magasin
  // aux licences : recevoir de l'argent sans activer l'app serait incorrect.
}

class VoiceInvitation {
  static const String endpoint = String.fromEnvironment(
    'LIVEKIT_INVITATION_ENDPOINT',
  );
  static bool get configured => MobileServices.httpsHost(endpoint);
  static Future<Room> join(String code) async {
    if (!configured || !RegExp(r'^[A-Za-z0-9-]{6,64}$').hasMatch(code))
      throw StateError('Invitation invalide.');
    final http.Response r = await http
        .post(
          Uri.parse(endpoint),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, String>{'code': code}),
        )
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200)
      throw StateError('Invitation expirée ou indisponible.');
    final Map<String, dynamic> json =
        jsonDecode(r.body) as Map<String, dynamic>;
    final Uri? url = Uri.tryParse(json['url'] as String? ?? '');
    final String token = json['token'] as String? ?? '';
    if (url == null ||
        url.scheme != 'wss' ||
        url.userInfo.isNotEmpty ||
        token.isEmpty ||
        token.length > 8192)
      throw StateError('Invitation invalide.');
    final Room room = Room();
    try {
      await room
          .connect(url.toString(), token)
          .timeout(const Duration(seconds: 12));
      return room;
    } catch (_) {
      await room.dispose();
      rethrow;
    }
  }
}
