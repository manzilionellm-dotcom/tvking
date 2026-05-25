// =========================================================
//  device_identity.dart — Identité unique de chaque install
// =========================================================
//  Génère et conserve un "MAC virtuel" propre à chaque
//  installation de l'app. Format inspiré des MAG box pour
//  être familier aux clients IPTV :
//      MK:A3:B2:F1:8E:91
//
//  "MK" = préfixe constant hérité (historique). On le conserve tel
//  quel après le rebrand 7 MOTION pour ne pas invalider les MACs
//  déjà émises chez les clients existants.
//  Les 5 octets suivants = aléatoires, générés au premier
//  lancement et stockés à vie dans SharedPreferences.
//
//  Cette MAC sert :
//    1. À identifier l'appareil pour l'admin (qui paie quoi)
//    2. Comme clé de lookup dans le JSON de configuration
//       distante (cf. RemoteConfigRepository)
//    3. À afficher dans About pour que le client puisse la
//       communiquer à son revendeur
// =========================================================

import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdentity {
  DeviceIdentity._();
  static final DeviceIdentity instance = DeviceIdentity._();

  static const String _kKey = 'device.virtual_mac.v1';
  static const String _kPrefix = 'MK';

  String? _cached;

  /// Renvoie le MAC virtuel — génère et persiste s'il n'existe pas.
  Future<String> get mac async {
    if (_cached != null) return _cached!;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String? stored = prefs.getString(_kKey);
    if (stored == null || !_isValid(stored)) {
      stored = _generate();
      await prefs.setString(_kKey, stored);
    }
    _cached = stored;
    return stored;
  }

  /// Valeur synchrone si déjà chargée, sinon "MK:??:??:??:??:??".
  String get macSync => _cached ?? 'MK:??:??:??:??:??';

  /// Pré-charge — à appeler une fois au démarrage de l'app.
  Future<void> preload() async {
    await mac;
  }

  /// Régénère un nouveau MAC (à utiliser uniquement en réglages
  /// avancés, prévenir l'utilisateur que ses associations admin
  /// seront perdues).
  Future<String> regenerate() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String fresh = _generate();
    await prefs.setString(_kKey, fresh);
    _cached = fresh;
    return fresh;
  }

  // ============================================================
  //  Helpers
  // ============================================================

  String _generate() {
    final Random rnd = Random.secure();
    final List<String> octets = List<String>.generate(
      5,
      (int _) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0').toUpperCase(),
    );
    return '$_kPrefix:${octets.join(':')}';
  }

  bool _isValid(String value) {
    final RegExp pattern = RegExp(
      r'^MK(?::[0-9A-F]{2}){5}$',
      caseSensitive: false,
    );
    return pattern.hasMatch(value);
  }
}
