// =========================================================
//  device_identity.dart — Identité unique de chaque install
// =========================================================
//  Génère et conserve un "MAC virtuel" propre à chaque
//  installation de l'app. Format inspiré des MAG box pour
//  être familier aux clients IPTV :
//      MK:A3:B2:F1:8E:91
//
//  "MK" = préfixe constant hérité (historique). On le conserve tel
//  quel après le rebrand The Few pour ne pas invalider les MACs
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

import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdentity {
  DeviceIdentity._();
  static final DeviceIdentity instance = DeviceIdentity._();

  static const String _kKey = 'device.virtual_mac.v1';
  static const String _kPrefix = 'MK';

  /// Channel natif qui expose l'ANDROID_ID (cf. MainActivity.kt). Sert
  /// à dériver une MAC STABLE entre réinstallations.
  static const MethodChannel _deviceChannel =
      MethodChannel('com.manzilionellm.tvking/device');

  String? _cached;

  /// Renvoie le MAC virtuel.
  ///
  /// Priorité :
  ///   1. MAC déjà stockée en local (on ne la change JAMAIS — un client
  ///      existant garde son identifiant, donc son abonnement).
  ///   2. Sinon (1er lancement OU réinstallation = SharedPreferences
  ///      effacé), on DÉRIVE une MAC déterministe depuis l'ANDROID_ID :
  ///      même appareil → même MAC, MÊME APRÈS RÉINSTALLATION. C'est ce
  ///      qui évite que le client perde son activation en réinstallant.
  ///   3. Si l'ANDROID_ID est indisponible (erreur, plateforme non
  ///      Android), repli sur une MAC aléatoire (ancien comportement).
  Future<String> get mac async {
    if (_cached != null) return _cached!;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? stored = prefs.getString(_kKey);
    if (stored != null && _isValid(stored)) {
      _cached = stored;
      return stored;
    }
    final String? androidId = await _stableDeviceId();
    String seed = (androidId ?? '').trim();
    if (seed.isEmpty) {
      // REPLI DURCI (anti-reset d'essai) : si l'ANDROID_ID manque (rare :
      // émulateurs, ROMs exotiques), on DÉRIVE d'une EMPREINTE MATÉRIELLE stable
      // (fabricant, modèle, build…) AU LIEU d'un aléatoire stocké localement qui
      // se réinitialisait à l'effacement des données. Conséquence : effacer les
      // données ne redonne plus un essai neuf, même sur ces appareils.
      // (Compromis assumé : 2 appareils STRICTEMENT identiques et sans
      // ANDROID_ID partageraient la même MAC — cas marginal.)
      final Map<String, String> info = await deviceInfo();
      seed = <String>[
        info['manufacturer'] ?? '',
        info['model'] ?? '',
        info['build'] ?? '',
        info['release'] ?? '',
        info['sdk'] ?? '',
      ].where((String s) => s.trim().isNotEmpty).join('|').trim();
    }
    final String derived = seed.isNotEmpty ? _macFromSeed(seed) : _generate();
    await prefs.setString(_kKey, derived);
    _cached = derived;
    return derived;
  }

  /// Lit l'ANDROID_ID via le channel natif. `null` si indisponible.
  Future<String?> _stableDeviceId() async {
    try {
      return await _deviceChannel.invokeMethod<String>('getAndroidId');
    } catch (_) {
      return null;
    }
  }

  String? _androidIdCache;

  /// ANDROID_ID brut (la graine de la MAC). Exposé pour le heartbeat → le
  /// panel peut afficher / rechercher par l'identifiant Android réel, en plus
  /// de la MAC virtuelle qui en dérive. `''` si indisponible.
  Future<String> androidId() async {
    if (_androidIdCache != null) return _androidIdCache!;
    final String? id = await _stableDeviceId();
    _androidIdCache = (id ?? '').trim();
    return _androidIdCache!;
  }

  /// Dérive 5 octets DÉTERMINISTES d'une graine (l'ANDROID_ID) via un
  /// hash FNV-1a (sans dépendance externe), puis formate en MK:XX:..:XX.
  /// Déterministe ⇒ même appareil = même MAC à chaque (ré)installation.
  String _macFromSeed(String seed) {
    int h = 0x811C9DC5; // FNV-1a 32-bit — offset basis
    for (final int b in utf8.encode('blackroyal:$seed')) {
      h = (h ^ b) & 0xFFFFFFFF;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    final List<String> octets = <String>[];
    for (int i = 0; i < 5; i++) {
      // Re-mixe entre chaque octet pour bien étaler les bits.
      h = (h ^ (h >> 13)) & 0xFFFFFFFF;
      h = (h * 0x01000193) & 0xFFFFFFFF;
      octets.add((h & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return '$_kPrefix:${octets.join(':')}';
  }

  /// Valeur synchrone si déjà chargée, sinon "MK:??:??:??:??:??".
  String get macSync => _cached ?? 'MK:??:??:??:??:??';

  /// Pré-charge — à appeler une fois au démarrage de l'app.
  Future<void> preload() async {
    await mac;
  }

  /// Cache des infos appareil (modèle, build Android…).
  Map<String, String>? _info;

  /// Infos de l'appareil Android (modèle, fabricant, version, numéro de
  /// build) via le channel natif. Sert au heartbeat pour que le panel
  /// recense chaque Android où l'app est installée. Map vide si indispo.
  Future<Map<String, String>> deviceInfo() async {
    if (_info != null) return _info!;
    try {
      final Object? raw =
          await _deviceChannel.invokeMethod<Object?>('getDeviceInfo');
      if (raw is Map) {
        _info = raw.map<String, String>((Object? k, Object? v) =>
            MapEntry<String, String>('$k', '${v ?? ''}'));
      } else {
        _info = <String, String>{};
      }
    } catch (_) {
      _info = <String, String>{};
    }
    return _info!;
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
