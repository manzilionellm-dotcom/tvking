// =========================================================
//  secret_cipher.dart — Chiffrement des identifiants au repos
// =========================================================
//  OBJECTIF : ne plus stocker le mot de passe Xtream EN CLAIR dans la base
//  SQLite. En cas de vol d'appareil ou d'extraction des fichiers de l'app
//  (adb backup, root…), l'abonnement IPTV payant du client ne doit pas être
//  lisible tel quel.
//
//  CLÉ : dérivée (SHA-256) de l'ANDROID_ID de l'appareil + un sel applicatif.
//  L'ANDROID_ID est lu À CHAUD via le plugin natif (jamais écrit sur disque) →
//  la clé n'apparaît NULLE PART dans les fichiers de l'app. Elle est
//  DÉTERMINISTE (même appareil ⇒ même clé), donc survit à une réinstallation
//  (les données locales, elles, sont effacées à la désinstallation de toute
//  façon).
//
//  ⚠️ PÉRIMÈTRE : chiffrement AU REPOS (sur l'appareil). La sauvegarde cloud
//  reste en clair pour l'instant (la restaurer sur une AUTRE box nécessiterait
//  une clé récupérable côté serveur — chantier backend séparé, cf. roadmap).
//
//  CONCEPTION « FAIL-OPEN » (sécurité défensive SANS casser la lecture) :
//  si la clé n'est pas disponible (ANDROID_ID absent, plateforme exotique,
//  erreur crypto…), on RETOMBE sur le clair — on ne lève JAMAIS, on ne bloque
//  JAMAIS la lecture. Le pire cas = comportement identique à aujourd'hui.
//  Les anciennes valeurs en clair (sans préfixe) restent lues telles quelles
//  → migration transparente, zéro perte de données.
// =========================================================
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SecretCipher {
  SecretCipher._();
  static final SecretCipher instance = SecretCipher._();

  // Même channel que DeviceIdentity / DeviceMemory (plugin tvking_device).
  static const MethodChannel _channel =
      MethodChannel('com.manzilionellm.tvking/device');

  /// Préfixe qui marque une valeur chiffrée par CETTE version. Une valeur sans
  /// ce préfixe est considérée comme du CLAIR hérité → lue telle quelle.
  static const String _marker = 'enc:v1:';

  /// Sel applicatif : sépare notre dérivation de clé de tout autre usage de
  /// l'ANDROID_ID. (Ce n'est pas un secret — la sécurité vient de l'ANDROID_ID.)
  static const String _salt = 'defew.tv.cred.v1';

  enc.Encrypter? _encrypter;
  bool _ready = false;

  /// Prépare la clé (idempotent, best-effort). À `await` AVANT toute lecture/
  /// écriture chiffrée (le repository le fait dans initialize / insert / read).
  Future<void> ensureReady() async {
    if (_ready) return;
    try {
      final String? androidId =
          await _channel.invokeMethod<String>('getAndroidId');
      if (androidId != null && androidId.isNotEmpty) {
        final List<int> digest =
            sha256.convert(utf8.encode('$_salt:$androidId')).bytes;
        _encrypter = enc.Encrypter(
          enc.AES(enc.Key(Uint8List.fromList(digest)), mode: enc.AESMode.gcm),
        );
      }
    } catch (_) {
      // Fail-open : pas de clé → on chiffrera/déchiffrera en NO-OP (clair).
    }
    _ready = true;
  }

  /// Chiffre [plain] → `enc:v1:<iv base64>:<ciphertext base64>`. Renvoie [plain]
  /// inchangé si vide ou si la clé n'est pas dispo (fail-open).
  String encrypt(String plain) {
    if (plain.isEmpty) return plain;
    final enc.Encrypter? e = _encrypter;
    if (e == null) return plain;
    try {
      final enc.IV iv = enc.IV.fromSecureRandom(16);
      final enc.Encrypted c = e.encrypt(plain, iv: iv);
      return '$_marker${iv.base64}:${c.base64}';
    } catch (_) {
      return plain; // jamais bloquant
    }
  }

  /// Déchiffre une valeur produite par [encrypt]. Une valeur SANS le préfixe
  /// (clair hérité) est renvoyée telle quelle. En cas d'échec, renvoie la
  /// valeur d'entrée (fail-open).
  String decrypt(String value) {
    if (!value.startsWith(_marker)) return value;
    final enc.Encrypter? e = _encrypter;
    if (e == null) return value;
    try {
      final String rest = value.substring(_marker.length);
      final int sep = rest.indexOf(':');
      if (sep < 0) return value;
      final enc.IV iv = enc.IV.fromBase64(rest.substring(0, sep));
      final enc.Encrypted c = enc.Encrypted.fromBase64(rest.substring(sep + 1));
      return e.decrypt(c, iv: iv);
    } catch (_) {
      return value;
    }
  }

  /// Réservé aux tests : injecte une clé déterministe sans passer par le
  /// plugin natif (indisponible en environnement de test).
  @visibleForTesting
  void debugSetKeyForTest(List<int> key32) {
    _encrypter = enc.Encrypter(
      enc.AES(enc.Key(Uint8List.fromList(key32)), mode: enc.AESMode.gcm),
    );
    _ready = true;
  }
}
