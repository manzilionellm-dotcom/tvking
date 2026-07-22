// =========================================================
//  secret_cipher.dart — Chiffrement des identifiants au repos
// =========================================================
//  OBJECTIF : ne plus stocker le mot de passe Xtream EN CLAIR dans la base
//  SQLite. En cas de vol d'appareil ou d'extraction des fichiers de l'app
//  (adb backup, root…), l'abonnement IPTV payant du client ne doit pas être
//  lisible tel quel.
//
//  CLÉ (v2, PRÉFÉRÉE) : racine de confiance MATÉRIELLE. Le plugin natif
//  (`getCredentialKey`) génère une DEK aléatoire de 32 octets, la conserve
//  ENVELOPPÉE par une clé AES-256-GCM du Android Keystore (TEE/StrongBox),
//  NON EXPORTABLE. Même avec le root ou un backup, l'attaquant récupère le
//  blob enveloppé mais PAS la clé racine → il ne peut pas déchiffrer. C'est
//  ce que la v1 ne garantissait pas.
//
//  CLÉ (v1, REPLI/HÉRITAGE) : dérivée (SHA-256) de l'ANDROID_ID + un sel
//  applicatif. Conservée UNIQUEMENT pour (a) relire les valeurs déjà
//  écrites en `enc:v1:` (migration transparente : elles seront ré-écrites en
//  v2 au prochain enregistrement), et (b) servir de repli sur les appareils
//  où le Keystore matériel est indisponible (API < 23, Keystore HS).
//  FAIBLESSE connue : l'ANDROID_ID est lisible sur l'appareil — la v1 ne
//  protège donc PAS contre le root/backup ; c'est précisément pourquoi la v2
//  la remplace dès qu'elle est disponible.
//
// PÉRIMÈTRE : chiffrement AU REPOS (sur l'appareil). La sauvegarde cloud
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

  /// Préfixes de version. Une valeur SANS préfixe = CLAIR hérité (lue telle
  /// quelle). `enc:v2:` = DEK matérielle (Keystore) ; `enc:v1:` = dérivée
  /// ANDROID_ID (héritage, encore lue mais plus jamais écrite si la v2 marche).
  static const String _markerV1 = 'enc:v1:';
  static const String _markerV2 = 'enc:v2:';

  /// Sel applicatif de la v1 : sépare notre dérivation de tout autre usage de
  /// l'ANDROID_ID. (Ce n'est pas un secret.)
  static const String _salt = 'defew.tv.cred.v1';

  /// Chiffreur v2 (DEK matérielle) — préféré. Null si Keystore indisponible.
  enc.Encrypter? _v2;

  /// Chiffreur v1 (ANDROID_ID) — repli d'écriture + lecture des anciennes
  /// valeurs `enc:v1:`.
  enc.Encrypter? _v1;

  bool _ready = false;

  /// Prépare les clés (idempotent, best-effort). À `await` AVANT toute
  /// lecture/écriture chiffrée (le repository le fait dans initialize /
  /// insert / read).
  Future<void> ensureReady() async {
    if (_ready) return;
    // 1) v2 : DEK matérielle enveloppée par le Keystore (racine non
    //    exportable). C'est le chemin PRÉFÉRÉ.
    try {
      final String? dekB64 =
          await _channel.invokeMethod<String>('getCredentialKey');
      if (dekB64 != null && dekB64.isNotEmpty) {
        final Uint8List dek = base64.decode(dekB64);
        if (dek.length == 32) {
          _v2 = enc.Encrypter(
            enc.AES(enc.Key(dek), mode: enc.AESMode.gcm),
          );
        }
      }
    } catch (_) {
      // Keystore indisponible (API < 23, HS) → on gardera la v1 en repli.
    }
    // 2) v1 : dérivée ANDROID_ID. Toujours préparée si possible, pour relire
    //    les anciennes valeurs `enc:v1:` (et servir de repli d'écriture si la
    //    v2 a échoué).
    try {
      final String? androidId =
          await _channel.invokeMethod<String>('getAndroidId');
      if (androidId != null && androidId.isNotEmpty) {
        final List<int> digest =
            sha256.convert(utf8.encode('$_salt:$androidId')).bytes;
        _v1 = enc.Encrypter(
          enc.AES(enc.Key(Uint8List.fromList(digest)), mode: enc.AESMode.gcm),
        );
      }
    } catch (_) {
      // Fail-open : pas de clé → NO-OP (clair).
    }
    _ready = true;
  }

  /// Chiffre [plain]. Utilise la v2 (matérielle) si dispo, sinon la v1, sinon
  /// renvoie [plain] inchangé (fail-open). Le préfixe encode la version pour
  /// que [decrypt] sache quelle clé employer.
  String encrypt(String plain) {
    if (plain.isEmpty) return plain;
    final bool useV2 = _v2 != null;
    final enc.Encrypter? e = useV2 ? _v2 : _v1;
    if (e == null) return plain;
    try {
      final enc.IV iv = enc.IV.fromSecureRandom(16);
      final enc.Encrypted c = e.encrypt(plain, iv: iv);
      final String marker = useV2 ? _markerV2 : _markerV1;
      return '$marker${iv.base64}:${c.base64}';
    } catch (_) {
      return plain; // jamais bloquant
    }
  }

  /// Déchiffre une valeur produite par [encrypt]. Route sur la bonne clé
  /// selon le préfixe. Une valeur SANS préfixe (clair hérité) est renvoyée
  /// telle quelle. En cas d'échec, renvoie la valeur d'entrée (fail-open).
  String decrypt(String value) {
    final bool isV2 = value.startsWith(_markerV2);
    final bool isV1 = value.startsWith(_markerV1);
    if (!isV2 && !isV1) return value; // clair hérité
    final String marker = isV2 ? _markerV2 : _markerV1;
    final enc.Encrypter? e = isV2 ? _v2 : _v1;
    if (e == null) return value;
    try {
      final String rest = value.substring(marker.length);
      final int sep = rest.indexOf(':');
      if (sep < 0) return value;
      final enc.IV iv = enc.IV.fromBase64(rest.substring(0, sep));
      final enc.Encrypted c = enc.Encrypted.fromBase64(rest.substring(sep + 1));
      return e.decrypt(c, iv: iv);
    } catch (_) {
      return value;
    }
  }

  /// Réservé aux tests : injecte une clé v1 déterministe sans passer par le
  /// plugin natif (indisponible en environnement de test). Produit du
  /// `enc:v1:` (la v2 exige la DEK matérielle, absente en test).
  @visibleForTesting
  void debugSetKeyForTest(List<int> key32) {
    _v1 = enc.Encrypter(
      enc.AES(enc.Key(Uint8List.fromList(key32)), mode: enc.AESMode.gcm),
    );
    _v2 = null;
    _ready = true;
  }

  /// Réservé aux tests : injecte une clé v2 déterministe (simule la DEK
  /// matérielle) pour valider le round-trip `enc:v2:` sans plugin natif.
  @visibleForTesting
  void debugSetV2KeyForTest(List<int> key32) {
    _v2 = enc.Encrypter(
      enc.AES(enc.Key(Uint8List.fromList(key32)), mode: enc.AESMode.gcm),
    );
    _ready = true;
  }
}
