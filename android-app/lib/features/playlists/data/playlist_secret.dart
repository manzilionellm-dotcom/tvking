// =========================================================
//  playlist_secret.dart — Mots de passe IPTV chiffrés sur la box
// =========================================================
//  Avant, la colonne `xtream_password` (et parfois l'URL M3U) était
//  en clair dans SQLite. Une copie du fichier de base suffisait.
//
//  Maintenant : AES-GCM, préfixe `enc1:`. Une ligne ancienne sans
//  préfixe est encore lue telle quelle, puis réécrite chiffrée au
//  prochain enregistrement. Si le chiffrement échoue, on garde le
//  clair plutôt que de perdre la liste du client.
//
//  La clé (32 octets) vit dans les préférences, pas dans le .db.
// =========================================================

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlaylistSecret {
  PlaylistSecret._();

  static const String prefix = 'enc1:';
  static const String _kKey = 'security.playlist_key_v1';

  /// Permet aux tests d'injecter une clé sans préférences.
  static Future<List<int>> Function()? keyLoader;

  static final AesGcm _algo = AesGcm.with256bits();

  static Future<List<int>> _key() async {
    final Future<List<int>> Function()? injected = keyLoader;
    if (injected != null) return injected();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? existing = prefs.getString(_kKey);
    if (existing != null && existing.isNotEmpty) {
      return base64Url.decode(existing);
    }
    final List<int> fresh = List<int>.generate(
      32,
      (_) => Random.secure().nextInt(256),
    );
    await prefs.setString(_kKey, base64Url.encode(fresh));
    return fresh;
  }

  /// Chiffre. `null` et le vide restent vides. Déjà chiffré : inchangé.
  static Future<String?> seal(String? plain) async {
    if (plain == null || plain.isEmpty) return plain;
    if (plain.startsWith(prefix)) return plain;
    try {
      final SecretBox box = await _algo.encrypt(
        utf8.encode(plain),
        secretKey: SecretKey(await _key()),
      );
      final List<int> packed = <int>[
        ...box.nonce,
        ...box.cipherText,
        ...box.mac.bytes,
      ];
      return '$prefix${base64Url.encode(packed)}';
    } catch (e) {
      if (kDebugMode) debugPrint('[PlaylistSecret] seal: $e');
      return plain;
    }
  }

  /// Déchiffre. Une valeur sans préfixe (ancienne ligne) est renvoyée
  /// telle quelle pour ne pas casser les listes déjà installées.
  static Future<String?> open(String? stored) async {
    if (stored == null || stored.isEmpty) return stored;
    if (!stored.startsWith(prefix)) return stored;
    try {
      final List<int> packed = base64Url.decode(stored.substring(prefix.length));
      if (packed.length < 12 + 16) return null;
      final List<int> nonce = packed.sublist(0, 12);
      final List<int> mac = packed.sublist(packed.length - 16);
      final List<int> cipher = packed.sublist(12, packed.length - 16);
      final List<int> clear = await _algo.decrypt(
        SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
        secretKey: SecretKey(await _key()),
      );
      return utf8.decode(clear);
    } catch (e) {
      if (kDebugMode) debugPrint('[PlaylistSecret] open: $e');
      return null;
    }
  }
}
