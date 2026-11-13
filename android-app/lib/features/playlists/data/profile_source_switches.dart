// =========================================================
//  profile_source_switches.dart — Les listes de CHAQUE profil
// =========================================================
//  Avant : une liste allumée l'était pour toute la maison.
//  Maintenant : chaque profil a ses propres interrupteurs. Le
//  profil A peut regarder le serveur 1 et le profil B le
//  serveur 2, sur la même box.
//
//  MIGRATION DOUCE (même idée que family_profile.dart)
//  ---------------------------------------------------
//  Le profil 1 garde EXACTEMENT ce qu'il avait : la colonne
//  `hidden` de la table `playlists`. On n'y touche pas.
//  Les autres profils ont un petit carnet dans SharedPreferences :
//  la liste des numéros de listes ÉTEINTES pour eux. Carnet vide
//  = tout est allumé, comme avant cette fonction.
//
//  Rien n'est téléchargé en double : les chaînes restent une
//  seule fois dans la base, on choisit seulement lesquelles on lit.
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../profiles/domain/family_profile.dart';

abstract final class ProfileSourceSwitches {
  /// Début de la clé ; la fin est l'id du profil (`p2`, `p3`…).
  static const String keyPrefix = 'zuno.profile_sources.off.v1.';

  static String keyFor(String profileId) => '$keyPrefix$profileId';

  /// Texte du carnet → numéros de listes éteintes.
  /// Un carnet abîmé vaut « rien d'éteint » : on préfère montrer
  /// une liste en trop plutôt qu'un écran vide.
  static Set<int> decode(String? raw) {
    if (raw == null || raw.isEmpty) return <int>{};
    try {
      final Object? data = jsonDecode(raw);
      if (data is! List) return <int>{};
      return <int>{
        for (final Object? v in data)
          if (v is int && v > 0) v,
      };
    } catch (_) {
      return <int>{};
    }
  }

  /// Numéros triés : le même carnet donne toujours le même texte.
  static String encode(Set<int> off) =>
      jsonEncode(off.where((int v) => v > 0).toList()..sort());

  /// Morceau de requête SQL qui écarte les listes éteintes.
  /// Seulement des entiers : rien qui vienne d'un texte saisi.
  static String sqlFilter(Set<int> off) {
    final List<int> ids = off.where((int v) => v > 0).toList()..sort();
    if (ids.isEmpty) return '';
    return ' AND playlist_id NOT IN (${ids.join(',')})';
  }

  /// Listes éteintes pour [profileId]. `null` pour le profil 1 :
  /// lui, c'est la colonne `hidden` de la base qui décide.
  static Future<Set<int>?> read(String profileId) async {
    if (ProfileKeys.isOrigin(profileId)) return null;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return decode(prefs.getString(keyFor(profileId)));
    } catch (e) {
      if (kDebugMode) debugPrint('[Profils] listes illisibles : $e');
      return <int>{};
    }
  }

  /// Allume ou éteint UNE liste pour UN profil (jamais le profil 1).
  static Future<void> write(String profileId, int playlistId,
      {required bool off}) async {
    if (ProfileKeys.isOrigin(profileId)) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Set<int> current = decode(prefs.getString(keyFor(profileId)));
      final bool changed =
          off ? current.add(playlistId) : current.remove(playlistId);
      if (!changed) return;
      await prefs.setString(keyFor(profileId), encode(current));
    } catch (e) {
      if (kDebugMode) debugPrint('[Profils] listes non enregistrées : $e');
    }
  }

  /// Même interrupteur pour TOUS les carnets déjà créés (ordre du
  /// panel, ou liste supprimée : son numéro ne doit pas traîner).
  static Future<void> writeAll(int playlistId, {required bool off}) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      for (final String key in prefs.getKeys().toList()) {
        if (!key.startsWith(keyPrefix)) continue;
        final Set<int> current = decode(prefs.getString(key));
        final bool changed =
            off ? current.add(playlistId) : current.remove(playlistId);
        if (changed) await prefs.setString(key, encode(current));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Profils] listes non enregistrées : $e');
    }
  }

  /// Efface le carnet d'un profil supprimé.
  static Future<void> drop(String profileId) async {
    if (ProfileKeys.isOrigin(profileId)) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(keyFor(profileId));
    } catch (_) {}
  }
}
