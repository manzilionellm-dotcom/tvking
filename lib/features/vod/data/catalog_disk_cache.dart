// =========================================================
//  catalog_disk_cache.dart — Cache disque GÉNÉRIQUE de catalogue (VOD)
// =========================================================
//  Socle commun des caches « façon Netflix » de VodRepository (films) et
//  SeriesRepository (séries) — une seule implémentation à maintenir (la
//  revue de code a montré que les deux copies divergeaient déjà).
//
//  Garanties (issues de la revue de code du 2026-07-16) :
//    • CLÉ DE SOURCE : le fichier mémorise l'empreinte du compte (serveur +
//      utilisateur Xtream). Au chargement, si la source active a CHANGÉ, le
//      cache est IGNORÉ ET SUPPRIMÉ → jamais le catalogue (ni les URLs à
//      identifiants) d'un ancien compte après un changement de source.
//    • Décodage/encodage en ISOLATE (compute) : plusieurs Mo de JSON ne
//      gèlent jamais le thread UI. Les fonctions de codec doivent être
//      TOP-LEVEL (contrainte des isolates).
//    • Fail-open : cache corrompu/illisible → null (on repart du réseau).
// =========================================================
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Codec d'un catalogue : chaîne JSON ↔ liste d'éléments. Les deux fonctions
/// DOIVENT être top-level (elles partent dans un isolate via [compute]).
class CatalogDiskCache<T> {
  CatalogDiskCache({
    required this.fileName,
    required this.decode,
    required this.encode,
  });

  final String fileName;

  /// (contenu brut du fichier) → éléments. Doit VÉRIFIER la version et
  /// renvoyer une liste vide si inconnue.
  final List<T> Function(String raw) decode;

  /// (éléments, clé de source) → contenu du fichier.
  final String Function((List<T>, String) input) encode;

  Future<File> _file() async {
    final Directory dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$fileName');
  }

  /// Extrait la clé de source stockée SANS décoder tout le catalogue :
  /// la clé est écrite en tête du JSON (préfixe court, lecture directe).
  static String? sourceKeyOf(String raw) {
    final RegExpMatch? m =
        RegExp(r'"k":"([^"]*)"').firstMatch(raw.length > 200 ? raw.substring(0, 200) : raw);
    return m?.group(1);
  }

  /// Charge le catalogue SI la clé de source correspond ; sinon supprime le
  /// fichier (catalogue d'un autre compte) et renvoie null.
  Future<List<T>?> load(String sourceKey) async {
    try {
      final File f = await _file();
      if (!await f.exists()) return null;
      final String raw = await f.readAsString();
      if (raw.isEmpty) return null;
      if (sourceKeyOf(raw) != sourceKey) {
        // Le cache appartient à une AUTRE source → on le jette (sécurité :
        // les streamUrl contiennent les identifiants de l'ancien compte).
        try {
          await f.delete();
        } catch (_) {}
        return null;
      }
      return await compute(decode, raw);
    } catch (e) {
      if (kDebugMode) debugPrint('[$fileName] cache illisible: $e');
      return null; // corrompu → réseau, sans crash
    }
  }

  Future<void> save(List<T> items, String sourceKey) async {
    try {
      final String raw = await compute(encode, (items, sourceKey));
      final File f = await _file();
      await f.writeAsString(raw, flush: true);
    } catch (e) {
      if (kDebugMode) debugPrint('[$fileName] cache non écrit: $e');
    }
  }
}

/// Politique commune du rafraîchissement silencieux (stale-while-revalidate).
/// Détection de changement ROBUSTE : longueur + empreinte de TOUS les ids
/// (l'ancienne heuristique premier/dernier id ratait un remplacement au
/// milieu du catalogue → écrans jamais notifiés).
bool catalogChanged(List<String> oldIds, List<String> newIds) {
  if (oldIds.length != newIds.length) return true;
  return Object.hashAll(oldIds) != Object.hashAll(newIds);
}
