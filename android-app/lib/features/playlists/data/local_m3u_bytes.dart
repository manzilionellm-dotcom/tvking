// =========================================================
//  local_m3u_bytes.dart — Lire un .m3u déjà sur la box
// =========================================================
//  Pas de réseau. On refuse un fichier vide ou plus gros que
//  le plafond d'import : une box d'entrée de gamme ne doit
//  pas charger un fichier sans fin. Le chemin vient du
//  sélecteur de documents Android, pas d'une adresse tapée.
// =========================================================

import 'dart:io';
import 'dart:typed_data';

import 'playlist_import_limits.dart';

class LocalM3uRead implements Exception {
  const LocalM3uRead(this.code);
  final String code;
  @override
  String toString() => code;
}

/// `local_empty` ou `local_too_big`.
Future<Uint8List> readLocalM3uBytes(String path) async {
  final File file = File(path);
  if (!await file.exists()) {
    throw const LocalM3uRead('local_empty');
  }
  final int length = await file.length();
  if (length <= 0) throw const LocalM3uRead('local_empty');
  if (length > kMaxM3uBytes) throw const LocalM3uRead('local_too_big');
  return file.readAsBytes();
}
