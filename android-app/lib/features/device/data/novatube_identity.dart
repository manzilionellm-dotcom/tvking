// =========================================================
//  novatube_identity.dart — Identité Atlas de l'édition NovaTube TV
// =========================================================
//  Dans l'édition NovaTube TV (--dart-define=NOVATUBE_TV=true), la box
//  s'enregistre dans Atlas comme application `app_novatube4k`, par les
//  routes authentifiées /api/novatube4k/* (déjà en production). Ces routes
//  demandent deux choses, gardées ici :
//
//    1. une « MAC brute » de 12 chiffres hexadécimaux (`raw_mac`).
//       Elle est DÉRIVÉE de l'identifiant Android de l'application
//       (ANDROID_ID, stable tant que l'app garde la même clé de signature),
//       puis mémorisée : la box garde la même fiche après une mise à jour ;
//
//    2. une CLÉ D'INSTALLATION aléatoire de 32 octets (64 caractères hexa).
//       Envoyée sous HTTPS dans l'en-tête X-Device-Key ; le serveur n'en
//       garde que l'empreinte SHA-256. Une autre clé ne peut pas réclamer
//       la fiche (protection contre l'usurpation d'une MAC).
//
//  Le code affiché au client, `MK:XX:XX:XX:XX:XX`, est calculé EXACTEMENT
//  comme le serveur (novatube4k.js, novatube4kAtlasMac) :
//      "MK:" + 5 premiers octets de SHA-256("novatube4k:" + RAW), en paires.
//  Il est donc correct même hors ligne, avant la première réponse.
//
//  Effacer les données de l'app détruit la clé : la fiche existante refuse
//  alors la nouvelle clé et propose une réassociation (code d'assistance
//  temporaire affiché sur la box, approuvé par l'administrateur).
// =========================================================
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_identity.dart';

class NovatubeIdentity {
  NovatubeIdentity._();
  static final NovatubeIdentity instance = NovatubeIdentity._();

  static const String kRawKey = 'novatube_tv.raw_mac.v1';
  static const String kDeviceKeyKey = 'novatube_tv.device_key.v1';
  static final RegExp _raw = RegExp(r'^[0-9A-F]{12}$');
  static final RegExp _deviceKey = RegExp(r'^[a-f0-9]{64}$');

  /// Graine de la MAC brute : l'ANDROID_ID de l'application. Remplaçable
  /// dans les tests (aucun canal Android dans `flutter test`).
  @visibleForTesting
  static Future<String> Function() seedProvider =
      () => DeviceIdentity.instance.androidId();

  String? _rawMac;
  String? _key;
  String? _mac;
  Future<void>? _loading;

  /// MAC brute (12 hexa majuscules) envoyée au serveur.
  Future<String> get rawMac async {
    await _load();
    return _rawMac!;
  }

  /// Clé d'installation (64 hexa minuscules), jamais affichée ni journalisée.
  Future<String> get deviceKey async {
    await _load();
    return _key!;
  }

  /// Code Atlas affiché au client : MK:XX:XX:XX:XX:XX.
  Future<String> get mac async {
    await _load();
    return _mac!;
  }

  /// Valeur synchrone si déjà chargée (sinon un gabarit neutre).
  String get macSync => _mac ?? 'MK:??:??:??:??:??';

  Future<void> _load() => _loading ??= _doLoad();

  Future<void> _doLoad() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String? raw = prefs.getString(kRawKey);
    if (raw == null || !_raw.hasMatch(raw)) {
      String seed = '';
      try {
        seed = (await seedProvider()).trim();
      } catch (_) {
        // Pas d'ANDROID_ID lisible : graine aléatoire, mémorisée juste après.
      }
      if (seed.isEmpty) seed = _randomHex(16);
      raw = await rawFromSeed(seed);
      await prefs.setString(kRawKey, raw);
    }
    String? key = prefs.getString(kDeviceKeyKey);
    if (key == null || !_deviceKey.hasMatch(key)) {
      key = _randomHex(32);
      await prefs.setString(kDeviceKeyKey, key);
    }
    _rawMac = raw;
    _key = key;
    _mac = await atlasMacFor(raw);
  }

  /// MAC brute dérivée d'une graine : 6 premiers octets de
  /// SHA-256("novatube-tv:" + graine), en hexadécimal majuscule.
  /// Le préfixe empêche qu'une autre app retrouve la même valeur.
  static Future<String> rawFromSeed(String seed) async {
    final Hash hash = await Sha256().hash(utf8.encode('novatube-tv:$seed'));
    return _hex(hash.bytes.sublist(0, 6)).toUpperCase();
  }

  /// Même formule que le serveur (novatube4k.js) : le code affiché par la
  /// box est celui que l'administrateur voit et active dans le panel.
  static Future<String> atlasMacFor(String raw) async {
    final Hash hash =
        await Sha256().hash(utf8.encode('novatube4k:${raw.toUpperCase()}'));
    final String h = _hex(hash.bytes.sublist(0, 5)).toUpperCase();
    return 'MK:${<String>[
      for (int i = 0; i < 10; i += 2) h.substring(i, i + 2),
    ].join(':')}';
  }

  static String _randomHex(int bytes) {
    final Random r = Random.secure();
    return _hex(List<int>.generate(bytes, (_) => r.nextInt(256)));
  }

  static String _hex(List<int> bytes) =>
      bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Tests : oublie l'identité en mémoire (les préférences restent).
  @visibleForTesting
  void resetForTesting() {
    _rawMac = null;
    _key = null;
    _mac = null;
    _loading = null;
  }
}
