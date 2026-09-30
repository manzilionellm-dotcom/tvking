// =========================================================
//  update_digest.dart — L'APK téléchargé est-il celui annoncé ?
// =========================================================
//  Le manifeste `version.json` PEUT porter `sha256` (hex, 64
//  caractères). S'il le porte, on compare. S'il ne le porte pas
//  (manifestes déjà en ligne), on ne bloque PAS la mise à jour :
//  refuser serait casser les téléphones déjà installés.
//
//  Ce n'est pas une preuve que personne ne peut remplacer l'APK
//  tant que le manifeste n'a pas d'empreinte. La signature Android
//  reste le verrou de l'installation par-dessus.
// =========================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// true si [expectedHex] est vide (pas d'empreinte annoncée) ou si
/// elle est égale au SHA-256 de [bytes]. false si elle est présente
/// mais différente, ou si elle n'a pas la forme d'un SHA-256.
bool apkDigestOk(Uint8List bytes, String expectedHex) {
  final String want = expectedHex.trim().toLowerCase();
  if (want.isEmpty) return true;
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(want)) return false;
  final String got = sha256.convert(bytes).toString();
  return got == want;
}

/// Lit `sha256` dans le manifeste. Absent ou mauvais type → ''.
String sha256FromManifest(Map<String, dynamic> json) {
  final Object? raw = json['sha256'];
  if (raw is! String) return '';
  return raw.trim().toLowerCase();
}

/// Empreinte hex d'un fichier déjà en mémoire (tests).
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Décode un manifeste JSON. null si ce n'est pas un objet.
Map<String, dynamic>? decodeManifest(String raw) {
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map(
        (Object? k, Object? v) => MapEntry<String, dynamic>('$k', v),
      );
    }
    return null;
  } catch (_) {
    return null;
  }
}
